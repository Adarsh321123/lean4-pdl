-- LOCAL TABLEAU


import Pdl.Syntax
import Pdl.Measures
import Pdl.Setsimp
import Pdl.Semantics
import Pdl.Discon
import Pdl.DagTableau
import Pdl.Vocab

open Undag

open HasLength

-- TABLEAU nodes

-- A tableau node has a set of formulas and one or no negated loaded formula.
def TNode := List Formula × List Formula × Option (Sum NegLoadFormula NegLoadFormula) -- ⟨L, R, o⟩
  deriving DecidableEq -- TODO Repr

-- Hint: use List.toFinset.ext_iff with this.
def TNode.setEqTo : TNode → TNode → Bool
| (L,R,O), (L',R',O') => L.toFinset == L'.toFinset ∧ R.toFinset == R'.toFinset ∧ O == O'

@[simp]
def TNode.L : TNode → List Formula := λ⟨L,_,_⟩ => L
@[simp]
def TNode.R : TNode → List Formula := λ⟨_,R,_⟩ => R
@[simp]
def TNode.O : TNode → Option (Sum NegLoadFormula NegLoadFormula) := λ⟨_,_,O⟩ => O

def TNode.isLoaded : TNode → Bool
| ⟨_, _, none  ⟩ => False
| ⟨_, _, some _⟩ => True

open HasVocabulary
def sharedVoc : TNode → Finset Char := λN => voc N.L ∩ voc N.R
instance tNodeHasVocabulary : HasVocabulary (TNode) := ⟨sharedVoc⟩

instance modelCanSemImplyTNode : vDash (KripkeModel W × W) TNode :=
  vDash.mk (λ ⟨M,w⟩ ⟨L, R, o⟩ => ∀ f ∈ L ∪ R ∪ (o.map (Sum.elim negUnload negUnload)).toList, evaluate M w f)

-- silly but useful:
instance modelCanSemImplyLLO : vDash (KripkeModel W × W) (List Formula × List Formula × Option (Sum NegLoadFormula NegLoadFormula)) :=
  vDash.mk (λ ⟨M,w⟩ ⟨L, R, o⟩ => ∀ f ∈ L ∪ R ∪ (o.map (Sum.elim negUnload negUnload)).toList, evaluate M w f)

-- Some thoughts about the TNode type:
-- - one formula may be loaded
-- - loading is not changed in local tableaux, but must be tracked through it.
-- - each (loaded) formula is left/right/both --> annotation or actually have two sets X1 and X2 here?
-- - also need to track loading and side "through" dagger tableau. (loading only for diamond dagger?)

-- LOCAL TABLEAU

-- Definition 9, page 15
-- A set X is closed  iff  0 ∈ X or X contains a formula and its negation.
def Closed : Finset Formula → Prop := fun X => ⊥ ∈ X ∨ ∃ f ∈ X, (~f) ∈ X

-- Local rules replace a given set of formulas by other sets, one for each branch.
-- (In Haskell this is "ruleFor" in Logic.PDL.Prove.Tree.)
inductive OneSidedLocalRule : List Formula → List (List Formula) → Type
  -- PROP LOGIC
  -- closing rules:
  | bot                 : OneSidedLocalRule [⊥]      ∅
  | not (φ   : Formula) : OneSidedLocalRule [φ, ~φ]  ∅
  | neg (φ   : Formula) : OneSidedLocalRule [~~φ]    [[φ]]
  | con (φ ψ : Formula) : OneSidedLocalRule [φ ⋀ ψ]  [[φ,ψ]]
  | nCo (φ ψ : Formula) : OneSidedLocalRule [~(φ⋀ψ)] [[~φ], [~ψ]]
  -- PROGRAMS
  -- one-child rules:
  | nTe (φ ψ)   : OneSidedLocalRule [~⌈?'φ⌉ψ]  [ [φ, ~ψ] ]
  | nSe (a b f) : OneSidedLocalRule [~⌈a;'b⌉f] [ [~⌈a⌉⌈b⌉f] ]
  | uni (a b f) : OneSidedLocalRule [⌈a⋓b⌉f]   [ [⌈a⌉f, ⌈b⌉f] ]
  | seq (a b f) : OneSidedLocalRule [⌈a;'b⌉f]  [ [⌈a⌉⌈b⌉f] ]
  -- splitting rules:
  | tes (f g)   : OneSidedLocalRule [⌈?'f⌉g]    [ [~f], [g] ]
  | nUn (a b f) : OneSidedLocalRule [~⌈a ⋓ b⌉f] [ [~⌈a⌉f], [~⌈b⌉f] ]
  -- STAR
  -- NOTE: we "manually" already make the first unravel/dagger step here to satisfy the (Neg)DagFormula type.
  | sta (a f) : OneSidedLocalRule [⌈∗a⌉f] (boxDagEndNodes ({f}, [ inject [a] a f ]))
  | nSt (a f) : OneSidedLocalRule [~⌈∗a⌉f] ([ [~f] ] ++ (dagEndNodes (∅, NegDagFormula.neg (inject [a] a f))))

theorem oneSidedLocalRuleTruth (lr : OneSidedLocalRule X B) : Con X ≡ discon B :=
  by
  intro W M w
  cases lr
  all_goals try (simp; done) -- takes care of all propositional rules
  all_goals try (aesop; done) -- takes care of three more rules

  case nUn a b φ => -- from {~⌈a ⋓ b⌉φ} to {~⌈a⌉φ} or {~⌈b⌉φ}
    constructor
    · aesop
    · intro w_X
      simp only [discon, Con, evaluate, Formula.or, ← or_iff_not_and_not] at w_X
      cases w_X
      all_goals aesop

  -- STAR RULES
  case nSt a φ =>
    constructor
    · -- soundness
      intro w_naSphi
      have := notStarSoundness M w a φ w_naSphi
      rcases this with ⟨Γ, Γ_in, w_Γ⟩
      rw [disconEval]
      simp [evaluatePoint,modelCanSemImplyList] at *
      aesop
    · -- invertibility
      intro w_X
      simp at w_X
      rw [disconEval] at w_X
      simp
      rcases w_X with ⟨Y,⟨Y_in, sat_Y⟩⟩
      cases Y_in
      · use w
        constructor
        · apply Relation.ReflTransGen.refl
        · simp at sat_Y; assumption
      · have := notStarInvert M w _ (by aesop) (~⌈a⌉⌈∗a⌉φ)
        simp [vDash, modelCanSemImplyDagTabNode] at this
        rcases this with ⟨z, w_a_z, y, z_aS_x, y_nf⟩
        use y
        constructor
        · apply Relation.ReflTransGen.head
          all_goals aesop
        · assumption

  case sta a f =>
    constructor
    · -- soundness
      intro Mw_X
      rw [disconEval]
      apply starSoundness M w ([f], [inject [a] a f])
      intro phi phi_in
      simp [vDash, undag, modelCanSemImplyDagTabNode, inject] at phi_in
      cases phi_in
      case inl phi_is_f =>
            subst phi_is_f
            simp at *
            apply Mw_X _ Relation.ReflTransGen.refl
      case inr phi_is_aaSf =>
            subst phi_is_aaSf
            simp at *
            intro v w_a_v z v_a_z
            exact Mw_X _ (Relation.ReflTransGen.head w_a_v v_a_z)
    · -- invertibility
      intro w_B
      have Mw_X := starInvert M w ([f], [inject [a] a f])
      specialize Mw_X _
      · rw [disconEval] at w_B
        exact w_B
      simp at *
      intro v w_aS_v
      cases Relation.ReflTransGen.cases_head w_aS_v
      case inl w_is_v =>
        subst w_is_v
        specialize Mw_X f
        simp at Mw_X
        exact Mw_X
      case inr hyp =>
        rcases hyp with ⟨z, w_a_z, z_aS_v⟩
        specialize Mw_X (⌈a⌉⌈∗a⌉f)
        simp at Mw_X
        exact Mw_X z w_a_z v z_aS_v


-- LOADED rule applications
-- Only the local rules ¬u, ¬; ¬* and ¬? may be applied to loaded formulas (MB page 19).
-- Each rule replaces the loaded formula by:
-- - up to one loaded formula,
-- - and a set of normal formulas.
-- It's annoying to need each rule twice here (due to the definition of LoadFormula).
inductive LoadRule : NegLoadFormula → List (List Formula × Option NegLoadFormula) → Type
  | nUn  {α β χ} : LoadRule (~'⌊α⋓β ⌋(χ : LoadFormula)) [ (∅, some (~'⌊α⌋χ)), (∅, some (~'⌊β⌋χ)) ]
  | nUn' {α β φ} : LoadRule (~'⌊α⋓β ⌋(φ : Formula    )) [ (∅, some (~'⌊α⌋φ)), (∅, some (~'⌊β⌋φ)) ]
  | nSe  {α β χ} : LoadRule (~'⌊α;'β⌋(χ : LoadFormula)) [ (∅, some (~'⌊α⌋⌊β⌋χ)) ]
  | nSe' {α β φ} : LoadRule (~'⌊α;'β⌋(φ : Formula    )) [ (∅, some (~'⌊α⌋⌊β⌋φ)) ]
  -- Now we use loaded dagger diamond tableau:
  | nSt  {α χ}   : LoadRule (~'⌊∗α  ⌋(χ : LoadFormula)) ([ (∅, some (~'χ)) ] ++
     loadDagEndNodes (∅, (Sum.inr (NegDagLoadFormula.neg (injectLoad α χ)))))
  | nSt' {α φ}   : LoadRule (~'⌊∗α  ⌋(φ : Formula    )) ([ ([~φ], none) ] ++
     loadDagEndNodes (∅, (Sum.inr (NegDagLoadFormula.neg (injectLoad' α φ)))))
  | nTe  {φt χ}  : LoadRule (~'⌊?'φt⌋(χ : LoadFormula)) [ ([φt], some (~'χ)) ]
  | nTe' {φt φ}  : LoadRule (~'⌊?'φt⌋(φ : Formula    )) [ ([φt, ~φ], none) ]

theorem loadRuleTruth (lr : LoadRule (~'χ) B) :
    (~(unload χ)) ≡ dis (B.map (λ (fs, o) => Con (fs ++ (o.map negUnload).toList))) :=
  by
  intro W M w
  cases lr

  case nTe => simp
  case nTe' => simp

  case nSe => aesop
  case nSe' => aesop

  case nUn α β χ =>
    have := oneSidedLocalRuleTruth (OneSidedLocalRule.nUn α β (unload χ)) W M w
    simp at *
    exact this
  case nUn' α β φ =>
    have := oneSidedLocalRuleTruth (OneSidedLocalRule.nUn α β φ) W M w
    simp at *
    exact this

  case nSt α χ =>
    constructor
    · -- soundness
      intro w_naSchi
      have := loadNotStarSoundness M w α χ w_naSchi
      rcases this with ⟨Γ, Γ_in, w_Γ⟩
      simp at Γ_in
      simp
      rw [disEvalHT, disEval]
      cases Γ_in
      case inl Γ_def =>
        subst Γ_def
        left
        apply w_Γ
        simp
      case inr Γ_in =>
        right
        simp only [List.mem_map, Prod.exists]
        refine ⟨?_, ⟨Γ.1, Γ.2, ?_⟩, ?_⟩
        · exact Con (Γ.1 ++ Option.toList (Option.map negUnload Γ.2))
        · simp; assumption
        · rw [conEval]; apply w_Γ
    · -- invertibility
      intro w_X
      simp [disEvalHT, disEval] at w_X
      cases w_X
      · simp; use w
      case inr hyp =>
        simp at hyp
        rcases hyp with ⟨f, ⟨Γ1, Γ2, ⟨Γ_in_ends, def_f⟩⟩, w_Γ⟩
        let thelf := NegDagLoadFormula.neg (DagLoadFormula.box α (DagLoadFormula.ldg α χ))
        have := loadNotStarInvert M w ([], Sum.inr thelf) ⟨⟨Γ1,Γ2⟩, ⟨Γ_in_ends, ?_⟩⟩
        · simp [vDash, modelCanSemImplyLoadDagTabNode, evaluateLDDTNode] at *
          rcases this with ⟨z, w_a_z, y, z_aS_x, y_nf⟩
          use y
          constructor
          · exact Relation.ReflTransGen.head w_a_z z_aS_x
          · assumption
        · intro g g_in -- for the ?_ above
          subst def_f
          rw [conEval] at w_Γ
          aesop
  case nSt' α φ =>
    -- analogous to nSt, but maybe need loadNotStarSoundness' with a φ instead of χ ??
    sorry

-- A LocalRule is a OneSidedLocalRule or a LoadRule.
-- Formulas can be in four places now: left, right, loaded left, loaded right.
inductive LocalRule : TNode → List TNode → Type
  | oneSidedL (orule : OneSidedLocalRule precond ress) : LocalRule (precond,∅,none) $ ress.map $ λ res => (res,∅,none)
  | oneSidedR (orule : OneSidedLocalRule precond ress) : LocalRule (∅,precond,none) $ ress.map $ λ res => (∅,res,none)
  | LRnegL (ϕ : Formula) : LocalRule ([ϕ], [~ϕ], none) ∅ --  ϕ occurs on the left side, ~ϕ on the right
  | LRnegR (ϕ : Formula) : LocalRule ([~ϕ], [ϕ], none) ∅ -- ~ϕ occurs on the left side,  ϕ on the right
  -- NOTE: do we need neg rules for ({unload χ}, ∅, some (Sum.inl ~χ)) and (∅, {unload χ}, some (Sum.inr ~χ)), ..here?
  -- Probably not, because then we could also have closed before/without loading!
  | loadedL (χ : LoadFormula) (lrule : LoadRule (~'χ) ress) :
      LocalRule (∅, ∅, some (Sum.inl (~'χ))) $ ress.map $ λ (X, o) => (X, ∅, o.map Sum.inl)
  | loadedR (χ : LoadFormula) (lrule : LoadRule (~'χ) ress) :
      LocalRule (∅, ∅, some (Sum.inr (~'χ))) $ ress.map $ λ (X, o) => (∅, X, o.map Sum.inr)

@[simp]
def applyLocalRule (_ : LocalRule (Lcond, Rcond, Ocond) ress) : TNode → List TNode
  | ⟨L, R, O⟩ => ress.map $ λ (Lnew, Rnew, Onew) => match Onew with
      | none                 => (L.diff Lcond ++ Lnew, R.diff Rcond ++ Rnew, O)
      | some (Sum.inl (~'χ)) => (L.diff Lcond ++ Lnew, R.diff Rcond ++ Rnew, some (Sum.inl (~'χ)))
      | some (Sum.inr (~'χ)) => (L.diff Lcond ++ Lnew, R.diff Rcond ++ Rnew, some (Sum.inr (~'χ)))

-- mathlib this?
@[simp]
instance Option.instHasSubsetOption : HasSubset (Option α) := HasSubset.mk
  λ o1 o2 =>
  match o1, o2 with
  | none, _ => True
  | some _, none => False
  | some f, some g => f = g

-- mathlib this?
@[simp]
theorem Option.some_subseteq {O : Option α} : (some x ⊆ O) ↔ some x = O := by
  cases O
  all_goals simp

inductive LocalRuleApp : TNode → List TNode → Type
  | mk {L R : List Formula}
       {C : List TNode}
       {ress : List TNode}
       (O : Option (Sum NegLoadFormula NegLoadFormula)) -- FIXME make implicit?
       (Lcond Rcond : List Formula)
       (Ocond : Option (Sum NegLoadFormula NegLoadFormula))
       (rule : LocalRule (Lcond, Rcond, Ocond) ress)
       {hC : C = applyLocalRule rule (L,R,O)}
       (preconditionProof : Lcond ⊆ L ∧ Rcond ⊆ R ∧ Ocond ⊆ O)
       : LocalRuleApp (L,R,O) C

theorem localRuleTruth
    {L R : List Formula}
    {C : List TNode}
    (O : Option (Sum NegLoadFormula NegLoadFormula))
    (lrA : LocalRuleApp (L,R,O) C) (M : KripkeModel W) (w : W)
  : (M,w) ⊨ (L,R,O) ↔ ∃ Ci ∈ C, (M,w) ⊨ Ci
  := by
  rcases lrA with ⟨_, Lcond, Rcond, Ocond, rule, preconditionProof⟩
  cases rule

  case oneSidedL ress orule hC =>
    have := oneSidedLocalRuleTruth orule W M w
    subst hC
    simp [applyLocalRule] at *
    sorry
  case oneSidedR ress orule hC =>
    have := oneSidedLocalRuleTruth orule W M w
    subst hC
    simp [applyLocalRule] at *
    sorry

  case LRnegL φ hC =>
    subst hC
    simp [applyLocalRule] at *
    intro hyp
    have := hyp φ
    have := hyp (~φ)
    aesop
  case LRnegR φ hC =>
    subst hC
    simp [applyLocalRule] at *
    intro hyp
    have := hyp φ
    have := hyp (~φ)
    aesop

  case loadedL ress χ lrule hC  =>
    have := loadRuleTruth lrule W M w
    rw [disEval] at this
    subst hC
    simp [applyLocalRule] at *
    subst preconditionProof
    simp [modelCanSemImplyForm,modelCanSemImplyLLO] at *
    constructor
    -- TODO: shorten/simplify this?
    · intro hyp
      have hyp' := hyp (~unload χ)
      simp at hyp'
      rw [this] at hyp'
      rcases hyp' with ⟨f, ⟨X , O, in_ress, def_f⟩, w_f⟩
      cases O
      · use (L ++ X, R, some (Sum.inl (~'χ)))
        constructor
        · use X, none
          simp only [Option.map_none', and_true]
          exact in_ress
        · intro g
          subst def_f
          rw [conEval] at w_f
          specialize hyp g
          aesop
      case some val =>
        use (L ++ X, R, some (Sum.inl val))
        constructor
        · use X, some val
          simp only [Option.map_some', and_true]
          exact in_ress
        · intro g g_in
          subst def_f
          rw [conEval] at w_f
          simp at *
          rcases g_in with ((g_in|g_in)|g_in)|g_in
          · simp_all only [true_or]
          · simp_all only [true_or]
          · simp_all only [or_true, true_or]
          · subst g_in
            apply w_f
            tauto
    · intro hyp
      rcases hyp with ⟨Ci, ⟨⟨X, O, ⟨in_ress, def_Ci⟩⟩, w_Ci⟩⟩
      intro f f_in
      subst def_Ci
      cases O
      all_goals simp at *
      · have := w_Ci f
        simp at this
        aesop
      case some val =>
        rcases f_in with (f_in|f_in)|f_in
        · apply w_Ci; simp_all
        · apply w_Ci; simp_all
        · subst f_in
          simp only [evaluate]
          rw [this]
          use Con (X ++ Option.toList (Option.map negUnload (some val)))
          constructor
          · use X, some val
          · rw [conEval]
            simp
            intro g g_in
            rcases g_in with (_|g_def)
            · apply w_Ci; simp_all
            · subst g_def; apply w_Ci; simp_all

  case loadedR ress χ lrule hC =>
    have := loadRuleTruth lrule W M w
    -- analogous to loadedL, but better shorten that first
    sorry

-- A set X is simple  iff  all P ∈ X are (negated) atoms or [A]_ or ¬[A]_.
@[simp]
def isSimpleForm : Formula → Bool
  | ⊥ => True -- TODO: change to False, covered by bot rule?
  | ~⊥ => True
  | ·_ => True
  | ~·_ => True
  | ⌈·_⌉_ => True
  | ~⌈·_⌉_ => True
  | _ => False

def isSimpleSet : Finset Formula → Bool
  | X => ∀ P ∈ X, isSimpleForm P

def isSimpleNode : TNode → Bool
  | (L, R, o) => ∀ f ∈ L ++ R ++ (o.map (Sum.elim negUnload negUnload)).toList, isSimpleForm f

-- MB: Definition 8
-- a local tableau for X, must be maximal
inductive LocalTableau : TNode → Type
  | byLocalRule {X B} (_ : LocalRuleApp X B) (next : ∀ Y ∈ B, LocalTableau Y) : LocalTableau X
  | sim {X} : isSimpleNode X → LocalTableau X

open LocalTableau

-- LOCAL END NODES AND TERMINATION

@[simp]
def lengthOfTNode : TNode -> ℕ
  | (L, R, none) => lengthOf L + lengthOf R
  | (L, R, some (Sum.inl (~'χ))) => lengthOf L + lengthOf R + lengthOf (~ unload χ)
  | (L, R, some (Sum.inr (~'χ))) => lengthOf L + lengthOf R + lengthOf (~ unload χ)

@[simp]
instance tnodeHasLength : HasLength TNode := ⟨lengthOfTNode⟩

-- needed for endNodesOf
instance localTableauHasSizeof : SizeOf (Σ X, LocalTableau X) :=
  ⟨fun ⟨X, _⟩ => lengthOf X⟩


-- TODO: is this even going to be true for our new system?
-- Maybe use a different measure than lengthOf? Also Dershowitz-Manna?
theorem localRuleApp.decreaseLength {X : TNode} {B : List TNode}
    (r : LocalRuleApp X B) : ∀ Y ∈ B, lengthOf Y < lengthOf X :=
  by
  cases r
  all_goals intro β inB; simp at *
  -- TODO: see Bml, first enable additional simps in Pdl.Setsimp
  all_goals sorry

-- open end nodes of a given localTableau
@[simp]
def endNodesOf : (Σ X, LocalTableau X) → List TNode
  | ⟨X, @byLocalRule _ B lr next⟩ =>
    (B.attach.map fun ⟨Y, h⟩ =>
      have : lengthOf Y < lengthOf X := localRuleApp.decreaseLength lr Y h
      endNodesOf ⟨Y, next Y h⟩).join
  | ⟨X, sim _⟩ => [X]
-- termination_by  -- Why is this not needed, even though "this" above is needed?
--   endNodesOf p => lengthOf p.1
