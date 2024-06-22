-- SOUNDNESS

import Pdl.Star
import Pdl.Tableau

import Mathlib.Tactic.Ring

open Classical

open HasSat

/-- ## Tools for saying that different kinds of formulas are in a TNode -/

@[simp]
instance : Membership Formula TNode :=
  ⟨fun φ X => φ ∈ X.L ∨ φ ∈ X.R⟩

@[simp]
def NegLoadFormula_in_TNode := fun nlf (X : TNode) => X.O = some (Sum.inl nlf) ∨ X.O = some (Sum.inr nlf)

@[simp]
instance NegLoadFormula.HasMem_TNode : Membership NegLoadFormula TNode := ⟨NegLoadFormula_in_TNode⟩

def AnyFormula := Sum Formula LoadFormula

inductive AnyNegFormula
| neg : AnyFormula → AnyNegFormula

local notation "~''" φ:arg => AnyNegFormula.neg φ

@[simp]
instance modelCanSemImplyAnyNegFormula {W : Type} : vDash (KripkeModel W × W) AnyNegFormula :=
  vDash.mk (λ ⟨M,w⟩ af => match af with
   | ⟨Sum.inl f⟩ => evaluate M w f
   | ⟨Sum.inr f⟩ => evaluate M w (unload f)
   )

@[simp]
def anyNegLoad : Program → AnyFormula → NegLoadFormula
| α, Sum.inl φ => ~'⌊α⌋φ
| α, Sum.inr χ => ~'⌊α⌋χ

local notation "~'⌊" α "⌋" χ => anyNegLoad α χ

-- set_option trace.Meta.synthInstance true -- turn this on to debug ∈ below.
@[simp]
def AnyNegFormula_in_TNode := fun (anf : AnyNegFormula) (X : TNode) => match anf with
| ⟨Sum.inl φ⟩ => (~φ) ∈ X
| ⟨Sum.inr χ⟩ => NegLoadFormula_in_TNode (~'χ) X -- FIXME: ∈ not working here

@[simp]
instance : Membership AnyNegFormula TNode := ⟨AnyNegFormula_in_TNode⟩

/-- ## Helper functions, TODO: move to (Local)Tableau.lean -/

-- TODO Computable version possible?
noncomputable def endNode_to_endNodeOfChildNonComp (lrA)
  (E_in: E ∈ endNodesOf (@LocalTableau.byLocalRule X _ lrA subTabs)) :
  @Subtype TNode (fun x => ∃ h, E ∈ endNodesOf (subTabs x h)) := by
  simp [endNodesOf] at E_in
  choose l h E_in using E_in
  choose c c_in l_eq using h
  subst l_eq
  use c
  use c_in

theorem endNodeIsEndNodeOfChild (lrA)
  (E_in: E ∈ endNodesOf (@LocalTableau.byLocalRule X _ lrA subTabs)) :
  ∃ Y h, E ∈ endNodesOf (subTabs Y h) := by
  have := endNode_to_endNodeOfChildNonComp lrA E_in
  use this
  aesop

theorem endNodeOfChild_to_endNode
    {X Y: TNode}
    {ltX}
    {C : List TNode}
    (lrA : LocalRuleApp X C)
    subTabs
    (h : ltX = LocalTableau.byLocalRule lrA subTabs)
    (Y_in : Y ∈ C)
    {Z : TNode}
    (Z_in: Z ∈ endNodesOf (subTabs Y Y_in))
    : Z ∈ endNodesOf ltX :=
  by
  cases h' : subTabs Y Y_in -- No induction needed for this!
  case sim Y_isSimp =>
    subst h
    simp
    use endNodesOf (subTabs Y Y_in)
    constructor
    · use Y, Y_in
    · exact Z_in
  case byLocalRule C' subTabs' lrA' =>
    subst h
    rw [h'] at Z_in
    simp
    use endNodesOf (subTabs Y Y_in)
    constructor
    · use Y, Y_in
    · rw [h']
      exact Z_in

/-- ## Navigating through tableaux with PathIn -/

-- To define ancestor / decendant relations inside tableaux we need to
-- represent both the whole Tableau and a specific node in it.
-- For this we use `PathInLocal` and `PathIn`.
-- They basically say "go to this child, then to this child, etc."
--
-- TODO: Do we need paths that go through/across multiple LocalTableau like
--       LHistories and unlike the Paths used in the Complteness Proof
--
-- TODO: Do we need paths that include back-loops?


-- UNUSED
inductive PathInLocal : ∀ {X}, LocalTableau X → Type
| byLocalRuleStep :
    (h : Y ∈ B)
    → PathInLocal (next Y h)
    → PathInLocal (LocalTableau.byLocalRule lrApp (next: ∀ Y ∈ B, LocalTableau Y))
| simEnd : PathInLocal (LocalTableau.sim _)

-- Three ways to make a path: empty, local step or pdl step.
-- The `loc` ad `pdl` steps correspond to two out of three constructors of `ClosedTableau`.
inductive PathIn : ∀ {H X}, ClosedTableau H X → Type
| nil : PathIn _
| loc : (Y_in : Y ∈ endNodesOf lt) → (tail : PathIn (next Y Y_in)) → PathIn (ClosedTableau.loc lt next)
| pdl : (r : PdlRule Γ Δ hfun) → PathIn (child : ClosedTableau (hfun Hist) Δ) → PathIn (ClosedTableau.pdl r child)

def tabAt : PathIn tab → Σ H X, ClosedTableau H X
| .nil => ⟨_,_,tab⟩
| .loc _ tail => tabAt tail
| .pdl _ p_child => tabAt p_child

def nodeAt {H X} {tab : (ClosedTableau H X)} : PathIn tab → TNode
| .nil => X
| .loc _ tail => nodeAt tail
| .pdl _ p_child => nodeAt p_child

def PathIn.append (p : PathIn tab) (q : PathIn (tabAt p).2.2) : PathIn tab := match p with
  | .nil => q
  | .loc Y_in tail => .loc Y_in (PathIn.append tail q)
  | .pdl r p_child => .pdl r (PathIn.append p_child q)

/-! ## Parents, Children, Ancestors and Descendants -/

-- TODO: adjust notation and s-t or t-s convention to notes!

/-- One-step children, with changed type. Use `children` instead. -/
def children' (p : PathIn tab) : List (PathIn (tabAt p).2.2) := match tabAt p with
  | ⟨_, _, ClosedTableau.loc lt _next⟩  =>
      ((endNodesOf lt).attach.map (fun ⟨Y,Y_in⟩ => [ .loc Y_in .nil ] )).join
  | ⟨_, _, ClosedTableau.pdl r _ct⟩  => [ .pdl r .nil ]
  | ⟨_, _, ClosedTableau.rep _⟩  => [ ]

/-- List of one-step children, given by paths from the same root. -/
def children (p : PathIn tab) : List (PathIn tab) := (children' p).map (PathIn.append p)

/-- The parent-child relation `s ◃ t` in a tableau -/
def stepRel {H X} {ctX : ClosedTableau H X} (s : PathIn ctX) (t : PathIn ctX) : Prop :=
  t ∈ children s

/-- Notation ◃ for `stepRel` -/
notation s:arg "◃" t:arg => stepRel s t

/-- Enable "<" notation for transitive closure of ◃ -/
instance : LT (PathIn tab) := ⟨TC stepRel⟩

/-- Trans closure of ◃ is denoted by <' -/
notation pa:arg "<'" pb:arg => TC stepRel pa pb

/-- ReflTrans closure of ◃ is denoted by ≤' -/
notation pa:arg "≤'" pb:arg => Relation.ReflTransGen stepRel pa pb

/-! ## K, ◃', edgesBeck, E -/

def K {H X} {ctX : ClosedTableau H X} : PathIn ctX → PathIn ctX → Prop
| t, s =>
    ∃ RRR, (tabAt t).2.2 = ClosedTableau.rep RRR -- t is a successful leaf
    ∧
    sorry -- TODO: say that s is the companion of t

/-- Successor relation plus back loops: ◃' (MB: page 26) -/
def edgesBack {H X} {ctX : ClosedTableau H X} (s : PathIn ctX) (t : PathIn ctX) : Prop :=
  s ◃ t  ∨  ∃ u, K s u ∧ u ◃ t

notation pa:arg "◃'" pb:arg => edgesBack pa pb

-- NOTE: for free nodes we have < iff <'

-- TODO: def companionOf : ...

def E {Hist X} {ctX : ClosedTableau Hist X} : PathIn ctX → PathIn ctX → Prop
| t, s => (t ◃ s) ∨ K t s

/-- We have: ◁′ = ◁ ∪ (K; ◁) -/
example : pa ◃' pb ↔ (pa ◃' pb) ∨ ∃ pc, K pa pc ∧ pc ◃ pb := by
  simp_all [edgesBack]


/-! ## ≡_E and Clusters -/

-- TODO: how to define the equivalence relation given by E:
-- Use EqvGen from Mathlib or maually as "both ways TC related"?

-- manual
def E_equiv {Hist X} {tab : ClosedTableau Hist X} (pa pb : PathIn tab) : Prop := TC E pa pb ∧ TC E pb pa

notation t:arg "≡_E" s:arg => E_equiv t s

-- better?
def E_equiv_maybe_this (tab : ClosedTableau Hist X) (pa pb : PathIn tab) : Prop := EqvGen E pa pb
def clusterOf (tab : ClosedTableau Hist X) (p : PathIn tab) := Quot.mk E p

def E_below {Hist X} {tab : ClosedTableau Hist X}
  (s t : PathIn tab) : Prop := TC E t s ∧ ¬ TC E s t

notation t:arg "⊏_E" s:arg => E_below t s

theorem eProp (tab : ClosedTableau Hist X) :
    Equivalence (@E_equiv _ _ tab)
    ∧
    WellFounded (@E_below _ _ tab) := by
  sorry

theorem eProp2 (tab : ClosedTableau Hist X) (s s' t : PathIn tab) :
      (s ◃ t → (t ⊏_E s) ∨ (t ≡_E s)) -- a
    ∧ (K s t → t ≡_E s) --b
    ∧ sorry -- s is free and s ◁ t, then t ⊏E s; -- c
    ∧ sorry -- s is loaded, t is free and s ◁ t, then t ⊏E s; --d
    ∧ (s ≡_E s' ∧ t ⊏_E s  →  t ⊏_E s') -- e
    ∧ (s <' t ∧ ¬(s ≡_E t)  →  t ⊏_E s) --f
  := by
sorry

/-! ## Soundness -/

theorem loadedDiamondPaths {Root Δ : TNode}
  (tab : ClosedTableau ([],[]) Root) -- ensure History = [] here to prevent repeats from "above".
  (path_to_Δ : PathIn tab)
  (h : Δ = nodeAt path_to_Δ)
  {M : KripkeModel W} {v : W}
  (φ : AnyFormula)
  (negLoad_in : NegLoadFormula_in_TNode (~'⌊α⌋φ) Δ) -- FIXME: ∈ not working here?
  (v_X : (M,v) ⊨ Δ)
  (v_α_w : relate M α v w)
  (w_φ : (M,w) ⊨ ~''φ)
  : ∃ Γ : TNode,
    ∃ path_to_Γ : PathIn tab,
        Γ = nodeAt path_to_Γ
      -- TODO: must be an extension of path_to_Δ
      ∧ (AnyNegFormula_in_TNode (~''φ) Γ) -- FIXME: ∈ not working here?
      ∧ (M,w) ⊨ Γ :=
  by
  have := eProp2 tab
  let ⟨L,R,O⟩ := Δ
  all_goals sorry


theorem tableauThenNotSat : ∀ X, ClosedTableau LoadHistory.nil X → ¬satisfiable X :=
  by
  intro X t
  -- by induction on the relation ⊏_E
  sorry


theorem correctness : ∀LR : TNode, satisfiable LR → consistent LR :=
  by
    intro LR
    contrapose
    unfold consistent
    unfold inconsistent
    simp only [not_nonempty_iff, not_isEmpty_iff, not_exists, not_forall, exists_prop, Nonempty.forall]
    intro hyp
    apply tableauThenNotSat LR hyp

theorem soundTableau : ∀φ, provable φ → ¬satisfiable ({~φ} : Finset Formula) :=
  by
    intro φ prov
    rcases prov with ⟨tabl⟩|⟨tabl⟩
    exact tableauThenNotSat ([~φ], [], none) tabl
    exact tableauThenNotSat ([], [~φ], none) tabl

theorem soundness : ∀φ, provable φ → tautology φ :=
  by
    intro φ prov
    apply notsatisfnotThenTaut
    rw [← singletonSat_iff_sat]
    apply soundTableau
    exact prov
