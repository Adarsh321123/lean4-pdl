import Mathlib.Data.Finset.Basic
import Mathlib.Tactic.Linarith
import Mathlib.Data.Set.Finite

import Pdl.Semantics
import Pdl.Star
import Pdl.Closure
import Pdl.DagSyntax

open Undag

-- FIXME: How can we avoid repeating this from Pdl.Syntax here?
-- (But not export it, so keep it "local" in two files!)
local notation "⌈" α "†⌉" φ => DagFormula.dag α φ
local notation "⌈" α "⌉" ψ => DagFormula.box α ψ
local notation "⌈⌈" ps "⌉⌉" df => DagFormula.boxes ps df

local notation "~" ψ => NegDagFormula.neg ψ

-- MEASURE
@[simp]
def mOfDagFormula : DagFormula → Nat
  | ⌈_†⌉ψ => mOfFormula ψ
  | ⌈α⌉ψ => mOfProgram α + mOfDagFormula ψ
-- how about negation?

--  | ~⌈_†⌉ψ => mOfFormula (~ψ)


@[simp]
instance : LT DagFormula := ⟨λ ψ1 ψ2 => mOfDagFormula ψ1 < mOfDagFormula ψ2⟩

def mOfDagNode : List Formula × Option NegDagFormula → ℕ
  | ⟨_, none⟩ => 0
  | ⟨_, some (~ψ)⟩ => 1 + mOfDagFormula ψ

-- -- -- DIAMONDS -- -- --

-- Immediate sucessors of a node in a Daggered Tableau, for diamonds.
@[simp]
def dagNext : (List Formula × Option NegDagFormula) → List (List Formula × Option NegDagFormula)
  | (fs, some (~⌈·a⌉ψ)) => [ (fs ++ [undag (~⌈·a⌉ψ)], none) ]
  | (fs, some (~⌈α⋓β⌉ψ)) => [ (fs, some (~⌈α⌉ψ))
                            , (fs, some (~⌈β⌉ψ)) ]
  | (fs, some (~⌈?'φ⌉ψ)) => [ (fs ++ [φ], some (~ψ)) ]
  | (fs, some (~⌈α;'β⌉ψ)) => [ (fs, some (~⌈α⌉⌈β⌉ψ)) ]
  | (fs, some (~⌈∗α⌉ψ)) => [ (fs, some (~ψ))
                            , (fs, some (~⌈α⌉⌈α†⌉(undag ψ))) ] -- only keep top-most dagger
  | (_, some (~⌈_†⌉_)) => [  ] -- delete branch
  | (_, none) => [ ] -- end node of dagger tableau

theorem mOfDagNode.isDec {x y : List Formula × Option NegDagFormula} (y_in : y ∈ dagNext x) :
    mOfDagNode y < mOfDagNode x := by
  rcases x with ⟨_, _|dfx⟩
  case none =>
    simp [mOfDagNode]
    cases y_in
  case some =>
    simp [mOfDagNode]
    rcases y with ⟨_, _|dfy⟩
    all_goals simp
    case some =>
      cases dfx
      case neg g =>
        cases g
        all_goals (try cases y_in)
        case box a f =>
          cases a
          all_goals (simp [dagNext] at *)
          case sequence =>
            rcases y_in with ⟨l,r⟩
            subst l
            subst r
            simp
            linarith
          case union a b =>
            rcases y_in with ⟨l,r⟩|⟨l,r⟩
            all_goals (subst l; subst r; simp; linarith)
          case star a =>
            rcases y_in with ⟨l,r⟩|⟨l,r⟩
            all_goals (subst l; subst r; simp <;> linarith)
          case test f =>
            rcases y_in with ⟨l,r⟩
            subst l
            subst r
            simp

@[simp]
def dagNextTransRefl : (List Formula × Option NegDagFormula) → List (List Formula × Option NegDagFormula) :=
  ftr dagNext mOfDagNode @mOfDagNode.isDec

instance modelCanSemImplyDagTabNode {W : Type} : vDash (KripkeModel W × W) (List Formula × Option NegDagFormula) :=
  vDash.mk (λ ⟨M,w⟩ (fs, mf) => ∀ φ ∈ fs ++ (mf.map undag).toList, evaluate M w φ)

-- Similar to Borzechowski's Lemma 4
theorem notStarSoundnessAux (a : Program) M (v w : W) (fs)
    (φ : DagFormula)
    (v_D : (M, v) ⊨ (fs, some (~⌈a⌉φ)))
    (v_a_w : relate M a v w)
    (w_nP : (M, w) ⊨ (~undag φ)) :
    ∃ Γ ∈ dagNextTransRefl (fs, ~⌈a⌉φ),
      (M, v) ⊨ Γ ∧ ( ( ∃ (a : Char) (as : List Program), (~ ⌈·a⌉⌈⌈as⌉⌉(undag φ)) ∈ Γ.1
                       ∧ relate M (Program.steps ([Program.atom_prog a] ++ as)) v w
                       ∧ Γ.2 = none )
                   ∨ ((~φ) ∈ Γ.2 ∧ v = w) ) := by
  cases a
  case atom_prog A =>
    use (fs ++ [undag (~⌈·A⌉φ)], none) -- unique successor by the "undag" rule
    constructor
    · unfold dagNextTransRefl; rw [ftr.iff]; right; simp; rw [ftr.iff]; simp
    · constructor
      · intro f
        specialize v_D f
        aesop
      · left
        use A, []
        simp at *
        exact v_a_w

  case star β =>
    simp at v_a_w
    have := starCases v_a_w
    cases this
    case inl v_is_w =>
      subst v_is_w
      use (fs, some (~φ))
      constructor
      · unfold dagNextTransRefl; rw [ftr.iff]; right; simp; rw [ftr.iff]; simp
      · constructor
        · intro f
          specialize v_D f
          intro f_in
          simp at f_in
          cases f_in
          · aesop
          case inr f_def =>
            subst f_def
            apply w_nP
        · right
          aesop
    case inr claim =>
      -- Here we follow the (fs, some (~⌈β⌉⌈β†⌉φ)) branch.
      rcases claim with ⟨_, ⟨u, v_neq_u, v_b_u, u_bS_w⟩⟩
      have := notStarSoundnessAux β M v u fs (⌈β†⌉(undag φ))
      specialize this _ v_b_u _
      · simp [modelCanSemImplyDagTabNode]
        intro f f_in
        simp [modelCanSemImplyForm] at *
        cases f_in
        case inl f_in =>
          apply v_D
          simp
          left
          assumption
        case inr f_eq =>
          subst f_eq
          simp
          use u
          constructor
          · exact v_b_u
          · use w
      · simp [modelCanSemImplyForm] at *
        use w
      rcases this with ⟨Γ, Γ_in, v_Γ, split⟩
      use Γ
      cases split
      case inl one =>
        constructor
        · unfold dagNextTransRefl; rw [ftr.iff]; simp; tauto
        · constructor
          · exact v_Γ
          · simp
            left
            simp [undag] at one
            rcases one with ⟨a, as, ⟨aasbs_in_, ⟨⟨y, a_v_y, y_as_u⟩, Γ_normal⟩⟩⟩
            use a, as ++ [∗β]
            constructor
            · rw [boxes_append]
              exact aasbs_in_
            · constructor
              · use y
                constructor
                · assumption
                · simp [relate_steps]
                  use u
              · assumption
      case inr two =>
        absurd two.right
        simp at v_neq_u
        exact v_neq_u

  case sequence β γ =>
    simp at v_a_w
    rcases v_a_w with ⟨u, v_β_u, u_γ_w⟩
    have u_nGphi : (M,u) ⊨ (~⌈γ⌉undag φ) := by
      simp [modelCanSemImplyForm] at *
      use w
    have := notStarSoundnessAux β M v u fs (⌈γ⌉φ)
    specialize this _ v_β_u u_nGphi
    · intro f
      simp
      intro f_in
      cases f_in
      case inl f_in =>
        apply v_D
        simp
        exact Or.inl f_in
      case inr f_eq =>
        rw [f_eq]
        simp
        simp [modelCanSemImplyForm] at u_nGphi
        use u
    rcases this with ⟨S, S_in, v_S, (⟨a,as,aasG_in_S,v_aas_u,Γ_normal⟩ | ⟨ngPhi_in_S, v_is_u⟩)⟩ -- Σ
    · use S -- "If (1), then we are done."
      constructor
      · unfold dagNextTransRefl; rw [ftr.iff]; simp; tauto
      · constructor
        · exact v_S
        · left
          simp
          use a, as ++ [γ]
          constructor
          · simp [undag] at  aasG_in_S
            rw [boxes_last]
            exact aasG_in_S
          · simp at v_aas_u
            rcases v_aas_u with ⟨y, v_a_y, y_asg_w⟩
            constructor
            · use y
              rw [relate_steps]
              constructor
              · exact v_a_y
              · use u
                aesop
            · assumption
    · -- "If (2) ..."
      have := notStarSoundnessAux γ M u w S.1 φ -- not use "fs" here!
      specialize this _ u_γ_w w_nP
      · intro f
        simp
        intro f_in
        cases f_in
        case inl f_in =>
          rw [v_is_u] at v_S
          apply v_S
          simp
          exact Or.inl f_in
        case inr f_eq =>
          rw [f_eq]
          exact u_nGphi
      rcases this with ⟨Γ, Γ_in, v_Γ, split⟩
      have also_in_prev : Γ ∈ dagNextTransRefl (fs, some (~⌈β;'γ⌉φ)) := by
        -- Here we use transitivity of "being a successor" in a dagger tableau.
        apply ftr.Trans Γ S (fs, some (~⌈β;'γ⌉φ))
        · convert Γ_in
        · rw [ftr.iff]; simp; right; exact S_in
      use Γ
      subst v_is_u
      constructor
      · exact also_in_prev
      · constructor
        · exact v_Γ
        · tauto --

  case union α β =>
    simp at v_a_w
    cases v_a_w
    case inl v_a_w =>
      have := notStarSoundnessAux α M v w fs φ
      specialize this _ v_a_w w_nP
      · intro f
        simp
        rintro (f_in_fs | fDef)
        · exact v_D f (by aesop)
        · subst fDef
          simp only [evaluate, not_forall, exists_prop, undag]
          use w
          simp [modelCanSemImplyForm,vDash] at w_nP
          tauto
      rcases this with ⟨Γ, Γ_in, v_Γ, split⟩
      use Γ
      constructor
      · unfold dagNextTransRefl; rw [ftr.iff]; simp; tauto
      · exact ⟨v_Γ, split⟩
    case inr v_b_w => -- completely analogous
      have := notStarSoundnessAux β M v w fs φ
      specialize this _ v_b_w w_nP
      · intro f
        simp
        rintro (f_in_fs | fDef)
        · exact v_D f (by aesop)
        · subst fDef
          simp only [evaluate, not_forall, exists_prop, undag]
          use w
          simp [modelCanSemImplyForm,vDash] at w_nP
          tauto
      rcases this with ⟨Γ, Γ_in, v_Γ, split⟩
      use Γ
      constructor
      · unfold dagNextTransRefl; rw [ftr.iff]; simp; tauto
      · exact ⟨v_Γ, split⟩

  case test ψ =>
    use (fs ++ [ψ], some (~φ)) -- unique successor
    constructor
    · unfold dagNextTransRefl; rw [ftr.iff]; right; simp; rw [ftr.iff]; simp
    · constructor
      · intro f f_in
        simp at *
        cases f_in
        · apply v_D
          simp
          tauto
        · specialize v_D (~⌈?'ψ⌉undag φ)
          simp at v_D
          aesop
      · right; aesop

termination_by
  notStarSoundnessAux α M v w fs φ v_D v_a_w w_nP => mOfProgram α

def dagEndNodes : (List Formula × Option NegDagFormula) → List (List Formula)
  | (fs, none) => [ fs ]
  | (fs, some df) => ((dagNext (fs, some df)).attach.map
      (fun ⟨gsdf, h⟩ =>
        have : mOfDagNode gsdf < mOfDagNode (fs, some df) := mOfDagNode.isDec h
        dagEndNodes gsdf)).join
termination_by
  dagEndNodes fs => mOfDagNode fs
decreasing_by simp_wf; assumption

theorem dagEnd_subset_next
    (O_in : Ω ∈ dagNext Γ) : dagEndNodes Ω ⊆ dagEndNodes Γ := by
  intro e
  rcases Γ with ⟨fs, mdf⟩
  rcases mdf with none | ⟨df⟩
  · simp [dagNext] at O_in
  · intro e_in
    unfold dagEndNodes
    aesop

theorem dagEndOfSome_iff_step : Γ ∈ dagEndNodes (fs, some (~⌈a⌉f)) ↔
    ∃ S ∈ dagNext (fs, some (~⌈a⌉f)), Γ ∈ dagEndNodes S := by
  cases a
  all_goals (simp [dagEndNodes]; done)

theorem dagEnd_subset_trf {Ω Γ} :
    Ω ∈ dagNextTransRefl Γ → dagEndNodes Ω ⊆ dagEndNodes Γ := by
  intro O_in
  unfold dagNextTransRefl at O_in
  rw [ftr.iff] at O_in
  cases O_in
  · aesop
  case inr hyp =>
    rcases hyp with ⟨S, S_in, O_in⟩
    have := dagEnd_subset_next S_in
    have := dagEnd_subset_trf O_in
    tauto
termination_by
  dagEnd_subset_trf Ω Γ hyp  => mOfDagNode Γ
decreasing_by simp_wf; apply mOfDagNode.isDec; assumption

-- A normal successor in a diamond dagger tableau is an end node.
theorem dagNormal_is_dagEnd
    (Γ_in : Γ ∈ dagNextTransRefl S)
    (Γ_normal : Γ.2 = none)
    :
    (Γ.1 ∈ dagEndNodes S) := by
  have := dagEnd_subset_trf Γ_in
  apply this
  rcases Γ with ⟨fs,odf⟩
  subst Γ_normal
  simp [dagEndNodes]

theorem notStarSoundness
    (M : KripkeModel W) (w : W) (a : Program) (φ : Formula)
    :
    evaluate M w (~⌈∗a⌉φ) →
      ∃ Γ ∈ [[~φ]] ++ dagEndNodes (∅, some (~⌈a⌉⌈a†⌉φ)), (M,w) ⊨ Γ :=
  by
      intro w_naSf
      simp at w_naSf
      rcases w_naSf with ⟨y, x_rel_y, y_nf⟩
      cases starCases x_rel_y -- NOTE: Relation.ReflTransGen.cases_head without ≠ is not enough here ...
      case inl w_is_y =>
        subst w_is_y
        use [~φ]
        simp [modelCanSemImplyForm, modelCanSemImplyList]
        exact y_nf
      case inr hyp =>
        -- (... because we need to get the in-equality here to get the contradiction below.)
        rcases hyp with ⟨_, z, w_neq_z, w_a_z, z_aS_y⟩
        -- MB now distinguishes whether a is atomic, we don't care.
        have := notStarSoundnessAux a M w z ([]) (DagFormula.dag a φ)
        specialize this _ w_a_z _
        · intro g g_in
          simp at g_in
          subst g_in
          simp
          exact ⟨z, ⟨w_a_z, ⟨y, ⟨z_aS_y, y_nf⟩⟩⟩⟩
        · simp [vDash,modelCanSemImplyForm]
          use y
        rcases this with ⟨Γ, Γ_in, w_Γ, caseOne | caseTwo⟩
        · rcases caseOne with ⟨A, as, _, _, Γ_normal⟩
          use Γ.1
          constructor
          · have := dagNormal_is_dagEnd Γ_in Γ_normal
            aesop
          · intro f f_in
            aesop
        · absurd caseTwo.2 -- contradiction!
          exact w_neq_z

theorem notStarInvertAux (M : KripkeModel W) (v : W) S :
    (∃ Γ ∈ dagNext S, (M, v) ⊨ Γ) → (M, v) ⊨ S := by
  intro hyp
  rcases hyp with ⟨Γ, Γ_in, v_Γ⟩
  rcases S with ⟨fs, none | ⟨⟨df⟩⟩⟩
  · simp [dagNext] at Γ_in
  · cases df
    case box a df =>
      cases a
      all_goals (simp at Γ_in; try cases Γ_in; all_goals try subst Γ_in)
      all_goals (intro f f_in; simp at f_in)
      case atom_prog =>
        cases f_in
        · apply v_Γ; simp at *; tauto
        case inr hyp => subst hyp; apply v_Γ; simp
      case sequence a b =>
        cases f_in
        · apply v_Γ; simp at *; tauto
        case inr hyp => subst hyp; specialize v_Γ (~⌈a⌉⌈b⌉(undag df)); aesop
      case union.inl a b Γ_is =>
        cases f_in
        · apply v_Γ; simp at *; aesop
        case inr hyp => subst hyp; specialize v_Γ (~⌈a⌉(undag df)); aesop
      case union.inr a b Γ_is =>
        cases f_in
        · apply v_Γ; simp at *; aesop
        case inr hyp => subst hyp; specialize v_Γ (~⌈b⌉(undag df)); aesop
      case star.inl a Γ_is =>
        cases f_in
        · apply v_Γ; simp at *; aesop
        case inr hyp =>
          subst hyp; subst Γ_is; specialize v_Γ (undag (~df)); simp at *
          use v
      case star.inr a Γ_is =>
        cases f_in
        · apply v_Γ; subst Γ_is; simp at *; aesop
        case inr hyp =>
          subst hyp; subst Γ_is;
          specialize v_Γ (~⌈a⌉⌈∗a⌉(undag df))
          simp at *
          rcases v_Γ with ⟨x, v_a_x, y, x_aS_y, y_nf⟩
          use y
          exact ⟨Relation.ReflTransGen.head v_a_x x_aS_y, y_nf⟩
      case test.refl g =>
        cases f_in
        · apply v_Γ; simp at *; aesop
        case inr hyp =>
          subst hyp
          simp
          constructor
          · specialize v_Γ g; aesop
          · specialize v_Γ (~(undag df)); simp at v_Γ; aesop
    case dag =>
      simp [dagNext] at Γ_in

-- Invertibility for nSt
theorem notStarInvert (M : KripkeModel W) (v : W) S
    :
    (∃ Γ ∈ dagEndNodes S, (M, v) ⊨ Γ) → (M, v) ⊨ S := by
  rintro ⟨Γ, Γ_in, v_Γ⟩
  rcases S_eq : S with ⟨fs, mdf⟩ -- explicit hypotheses in rcases are needed to prove termination
  subst S_eq
  cases mdf_eq : mdf
  case none =>
    subst mdf
    simp [dagEndNodes] at Γ_in
    subst Γ_in
    simp [modelCanSemImplyDagTabNode]
    exact v_Γ
  case some ndf =>
    subst mdf
    rcases ndf_eq : ndf with ⟨df⟩
    subst ndf_eq
    cases df_eq : df
    case dag =>
      subst df_eq
      simp [dagEndNodes] at Γ_in
    case box a f =>
      subst df_eq
      rw [dagEndOfSome_iff_step] at Γ_in
      rcases Γ_in with ⟨T, T_in, Γ_in⟩
      have v_T := notStarInvert M v T ⟨Γ, ⟨Γ_in, v_Γ⟩⟩ -- recursion!
      exact notStarInvertAux M v (fs , ~⌈a⌉f) ⟨_, ⟨T_in, v_T⟩⟩
termination_by
  notStarInvert M v S claim => mOfDagNode S
decreasing_by simp_wf; apply mOfDagNode.isDec; aesop


-- -- LOADED DIAMONDS -- --

inductive DagLoadFormula
  | dag : Program → Formula → DagLoadFormula -- ⌊α†⌋φ
  | ldg : Program → LoadFormula → DagLoadFormula -- ⌊α†⌋χ
  | box : Program → DagLoadFormula → DagLoadFormula  -- ⌊α⌋γ
  deriving Repr, DecidableEq

local notation "⌊" α "†⌋" φ => DagLoadFormula.dag α (φ : Formula)
local notation "⌊" α "†⌋" χ => DagLoadFormula.ldg α (χ : LoadFormula)
local notation "⌊" α "⌋" γ => DagLoadFormula.box α (γ : DagLoadFormula)
local notation "⌊⌊" ps "⌋⌋" γ => DagLoadFormula.boxes ps (γ : DagLoadFormula)

-- Given α and χ, define ⌊α⌋⌊α†⌋χ
@[simp]
def injectLoad : Program → LoadFormula → DagLoadFormula
  | α, χ => (DagLoadFormula.box α (DagLoadFormula.ldg α χ))

-- Given α and φ, define ⌊α⌋⌊α†⌋φ
@[simp]
def injectLoad' : Program → Formula → DagLoadFormula
  | α, φ => (DagLoadFormula.box α (DagLoadFormula.dag α φ))

inductive NegDagLoadFormula
  | neg : DagLoadFormula → NegDagLoadFormula

open NegDagLoadFormula

local notation "~" γ => NegDagLoadFormula.neg γ

@[simp]
def unloadAndUndag : DagLoadFormula → Formula
  | (⌊α†⌋(φ : Formula)) => (Formula.box (∗α) φ)
  | (⌊α†⌋(χ : LoadFormula)) => (Formula.box (∗α) (unload χ))
  | (⌊α⌋γ) => (Formula.box α (unloadAndUndag γ))

def undagOnly : DagLoadFormula → LoadFormula
  | (⌊α†⌋(φ : Formula)) => (LoadFormula.load (∗α) φ)
  | (⌊α†⌋(χ : LoadFormula)) => (LoadFormula.box (∗α) (χ))
  | (⌊α⌋γ) => (LoadFormula.box α (undagOnly γ))

def unloadOnly : DagLoadFormula → DagFormula -- probably never needed?
  | (⌊α†⌋(φ : Formula)) => (DagFormula.dag (∗α) φ)
  | (⌊α†⌋(χ : LoadFormula)) => (DagFormula.dag (∗α) (unload χ))
  | (⌊α⌋γ) => (DagFormula.box α (unloadOnly γ))

@[simp]
theorem unloadUndagOnly: unload (undagOnly γ) = unloadAndUndag γ := by
  induction γ
  all_goals simp_all

example : DagLoadFormula := ⌊(·'a')†⌋(·'p')
example : DagLoadFormula := ⌊(·'a')†⌋⌊·'a'⌋(·'p') -- should this be allowed?!
example : DagLoadFormula := ⌊·'a'⌋⌊(·'a')†⌋(·'p')

-- In an LDDT we have a list of normal formulas and optionally either a NegLoadFormula or a NegDagLoadFormula.

def LDDTNode := List Formula × Sum NegLoadFormula NegDagLoadFormula

@[simp]
def LDDTNode.isDagFree : LDDTNode → Bool
| ⟨_, Sum.inl _⟩ => True
| ⟨_, Sum.inr _⟩ => False

-- TODO: All things we had for normal (= unloaded) diamonds
-- we now need also for loaded here, i.e. anaologons of:
--
-- [X] dagNext --> loadDagNext
-- [X] mOfDagNode --> mOfLoadDagNode
-- [X] mOfDagNode.isDec --> mOfLoadDagNode.isDec
-- [X] dagNextTransRefl --> loadDagNextTransRefl
-- [X] modelCanSemImplyDagTabNode --> modelCanSemImplyLoadDagTabNode(')
-- [X] notStarSoundnessAux --> loadNotStarSoundnessAux
-- [X] dagEndNodes --> loadDagEndNodes
-- [X] dagEnd_subset_next --> loadDagEnd_subset_next
-- [X] dagEndOfSome_iff_step --> loadDagEndOfSome_iff_step
-- [X] dagEnd_subset_trf --> loadDagEnd_subset_trf
-- [X] dagNormal_is_dagEnd --> loadDagNormal_is_loadDagEnd
-- [X] notStarSoundness --> loadNotStarSoundness
-- [X] notStarInvertAux --> loadNotStarInvertAux
-- [X] notStarInvert --> loadNotStarInvert

-- Immediate sucessors of a node in a Loaded Daggered Diamond Tableau (LDDT).
-- Question: can it be that ψ is unloaded but not yet undaggered?!
-- Answer No. Note that we use "undagOnly" but never "unloadOnly".
@[simp]
def loadDagNext : LDDTNode → List LDDTNode
  | (fs, Sum.inr (~⌊·a⌋(ψ : DagLoadFormula))) => [ (fs, (Sum.inl (~'(⌊·a⌋(undagOnly ψ))))) ]
  | (fs, Sum.inr (~⌊α⋓β⌋ψ)) => [ (fs, (Sum.inr (~⌊α⌋ψ)))
                                 , (fs, (Sum.inr (~⌊β⌋ψ))) ]
  | (fs, Sum.inr (~⌊?'φ⌋ψ)) => [ (fs ++ [φ], (Sum.inr (~ψ))) ]
  | (fs, Sum.inr (~⌊α;'β⌋ψ)) => [ (fs, (Sum.inr (~⌊α⌋⌊β⌋ψ))) ]
  | (fs, Sum.inr (~⌊∗α⌋ψ)) => [ (fs, (Sum.inr (~ψ)))
                                , (fs, (Sum.inr (~⌊α⌋⌊α†⌋(undagOnly ψ)))) ] -- only keep top-most dagger
  | (_, Sum.inr (~⌊_†⌋(_ : Formula))) => [  ] -- delete branch
  | (_, Sum.inr (~⌊_†⌋(_ : LoadFormula))) => [  ] -- delete branch
  | (_, Sum.inl _) => [ ] -- end node of dagger tableau

def mOfLoadDagNode : LDDTNode → ℕ
  | ⟨_, Sum.inl _⟩ => 0
  | ⟨_, Sum.inr (~ψ)⟩ => 1 + mOfDagFormula (unloadOnly ψ)

theorem mOfLoadDagNode.isDec {x y : LDDTNode} (y_in : y ∈ loadDagNext x) :
    mOfLoadDagNode y < mOfLoadDagNode x := by
    rcases x with ⟨_, lfx|dlfx⟩
    case inl =>
      simp [mOfLoadDagNode]
      cases y_in
    case inr =>
      simp [mOfLoadDagNode]
      rcases y with ⟨_, lfy|dlfy⟩
      all_goals simp
      case inr =>
        cases dlfx
        case neg g =>
        cases g
        all_goals (try cases y_in)
        case box a f =>
          cases a
          all_goals (simp [dagNext,unloadOnly] at *)
          case atom_prog =>
            rcases y_in with ⟨l,r⟩
          case sequence =>
            rcases y_in with ⟨l,r⟩
            simp
            linarith
          case union a b =>
            rcases y_in with ⟨l,r⟩|⟨l,r⟩
            all_goals (simp; linarith)
          case star a =>
            rcases y_in with ⟨l,r⟩|⟨l,r⟩
            all_goals (simp <;> linarith)
          case test f =>
            rcases y_in with ⟨l,r⟩
            simp

@[simp]
def loadDagNextTransRefl : LDDTNode → List LDDTNode :=
  ftr loadDagNext mOfLoadDagNode @mOfLoadDagNode.isDec

@[simp]
def toFormula : NegLoadFormula ⊕ NegDagLoadFormula → Formula
  | Sum.inl (~'f) => ~unload f
  | Sum.inr (~(f: DagLoadFormula)) => ~unloadAndUndag f

def evaluateLDDTNode: KripkeModel W × W → LDDTNode → Prop :=
  λ ⟨M,w⟩ (fs, mf) => ∀ φ ∈ fs ++ [toFormula mf], evaluate M w φ

-- FIXME: this should not be needed / covered by the non-' instance.
instance modelCanSemImplyLoadDagTabNode' {W : Type} : vDash (KripkeModel W × W)
  (List Formula × Sum NegLoadFormula NegDagLoadFormula) :=
  vDash.mk evaluateLDDTNode

instance modelCanSemImplyLoadDagTabNode {W : Type} : vDash (KripkeModel W × W) LDDTNode :=
  vDash.mk evaluateLDDTNode

-- Similar to Borzechowski's Lemma 4
theorem loadNotStarSoundnessAux (a : Program) M (v w : W) (fs)
    (φ : DagLoadFormula)
    (v_D : (M, v) ⊨ ((fs, Sum.inr (~⌊a⌋φ)) : LDDTNode))
    (v_a_w : relate M a v w)
    (w_nP : (M, w) ⊨ (~unloadAndUndag φ)):
    ∃ Γ ∈ loadDagNextTransRefl (fs, Sum.inr (~⌊a⌋φ)),
      (M, v) ⊨ Γ ∧ ( ( ∃ (a : Char) (as : List Program), Sum.inl (~' ⌊·a⌋⌊⌊as⌋⌋(undagOnly φ)) = Γ.2
                       ∧ relate M (Program.steps ([Program.atom_prog a] ++ as)) v w
                       ∧ Γ.isDagFree )
                   ∨ (Sum.inr (~φ) = Γ.2 ∧ v = w) ) := by
  cases a
  case atom_prog A =>
    use (fs, Sum.inl (~' ⌊·A⌋(undagOnly φ))) -- unique successor by the "undag" rule
    constructor
    · unfold loadDagNextTransRefl; rw [ftr.iff]; right; simp; rw [ftr.iff]; simp
    · constructor
      · intro f
        specialize v_D f
        simp_all
      · left
        use A, []
        simp at *
        exact v_a_w
  case star β =>
    simp at v_a_w
    have := starCases v_a_w
    cases this
    case inl v_is_w =>
      subst v_is_w
      use (fs, Sum.inr (~φ))
      constructor
      · unfold loadDagNextTransRefl; rw [ftr.iff]; right; simp; rw [ftr.iff]; simp
      · constructor
        · intro f
          specialize v_D f
          intro f_in
          simp at f_in
          cases f_in
          · aesop
          case inr f_def =>
            subst f_def
            apply w_nP
        · right
          aesop
    case inr claim =>
      -- Here we follow the (fs, ~⌈β⌉⌈β†⌉φ) branch.
      rcases claim with ⟨_, ⟨u, v_neq_u, v_b_u, u_bS_w⟩⟩
      have := loadNotStarSoundnessAux β M v u fs (⌊β†⌋(undagOnly φ))
      specialize this _ v_b_u _
      · simp [modelCanSemImplyLoadDagTabNode']
        intro f f_in
        simp [modelCanSemImplyForm] at *
        cases f_in
        case inl f_in =>
          apply v_D
          simp
          left
          assumption
        case inr f_eq =>
          subst f_eq
          simp
          use u
          constructor
          · exact v_b_u
          · use w
      · simp [modelCanSemImplyForm] at *
        use w
      rcases this with ⟨Γ, Γ_in, v_Γ, split⟩
      use Γ
      cases split
      case inl one =>
        constructor
        · unfold loadDagNextTransRefl; rw [ftr.iff]; simp; tauto
        · constructor
          · exact v_Γ
          · simp
            left
            simp [undag] at one
            rcases one with ⟨a, as, ⟨aasbs_in_, ⟨⟨y, a_v_y, y_as_u⟩, Γ_normal⟩⟩⟩
            use a, as ++ [∗β]
            constructor
            · rw [loadBoxes_append]
              exact aasbs_in_
            · constructor
              · use y
                constructor
                · assumption
                · simp [relate_steps]
                  use u
              · assumption
      case inr two =>
        absurd two.right
        simp at v_neq_u
        exact v_neq_u

  case sequence β γ =>
    simp at v_a_w
    rcases v_a_w with ⟨u, v_β_u, u_γ_w⟩
    have u_nGphi : (M,u) ⊨ (~⌈γ⌉unloadAndUndag φ) := by
      simp [modelCanSemImplyForm] at *
      use w
    have := loadNotStarSoundnessAux β M v u fs (⌊γ⌋φ)
    specialize this _ v_β_u u_nGphi
    · intro f
      simp
      intro f_in
      cases f_in
      case inl f_in =>
        apply v_D
        simp
        exact Or.inl f_in
      case inr f_eq =>
        rw [f_eq]
        simp
        simp [modelCanSemImplyForm] at u_nGphi
        use u
    rcases this with ⟨S, S_in, v_S, (⟨a,as,aasG_in_S,v_aas_u,Γ_normal⟩ | ⟨ngPhi_in_S, v_is_u⟩)⟩ -- Σ
    · use S -- "If (1), then we are done."
      constructor
      · unfold loadDagNextTransRefl; rw [ftr.iff]; simp; tauto
      · constructor
        · exact v_S
        · left
          simp
          use a, as ++ [γ]
          constructor
          · rw [loadBoxes_last]
            convert aasG_in_S
          · simp at v_aas_u
            rcases v_aas_u with ⟨y, v_a_y, y_asg_w⟩
            constructor
            · use y
              rw [relate_steps]
              constructor
              · exact v_a_y
              · use u
                aesop
            · assumption
    · -- "If (2) ..."
      have := loadNotStarSoundnessAux γ M u w S.1 φ -- not use "fs" here!
      specialize this _ u_γ_w w_nP
      · intro f
        simp
        intro f_in
        cases f_in
        case inl f_in =>
          rw [v_is_u] at v_S
          apply v_S
          simp
          exact Or.inl f_in
        case inr f_eq =>
          rw [f_eq]
          exact u_nGphi
      rcases this with ⟨Γ, Γ_in, v_Γ, split⟩
      have also_in_prev : Γ ∈ loadDagNextTransRefl (fs, Sum.inr (~⌊β;'γ⌋φ)) := by
        -- Here we use transitivity of "being a successor" in a dagger tableau.
        apply ftr.Trans Γ S (fs, Sum.inr (~⌊β;'γ⌋φ))
        · convert Γ_in
          rcases S with ⟨S1,S2⟩
          simp_all
        · rw [ftr.iff]; simp; right; exact S_in
      use Γ
      subst v_is_u
      constructor
      · exact also_in_prev
      · constructor
        · exact v_Γ
        · tauto --

  case union α β =>
    simp at v_a_w
    cases v_a_w
    case inl v_a_w =>
      have := loadNotStarSoundnessAux α M v w fs φ
      specialize this _ v_a_w w_nP
      · intro f
        simp
        rintro (f_in_fs | fDef)
        · exact v_D f (by aesop)
        · subst fDef
          simp only [toFormula, unloadAndUndag, evaluate, not_forall, exists_prop, undag]
          use w
          simp [modelCanSemImplyForm,vDash] at w_nP
          tauto
      rcases this with ⟨Γ, Γ_in, v_Γ, split⟩
      use Γ
      constructor
      · unfold loadDagNextTransRefl; rw [ftr.iff]; simp; tauto
      · exact ⟨v_Γ, split⟩
    case inr v_b_w => -- completely analogous
      have := loadNotStarSoundnessAux β M v w fs φ
      specialize this _ v_b_w w_nP
      · intro f
        simp
        rintro (f_in_fs | fDef)
        · exact v_D f (by aesop)
        · subst fDef
          simp only [toFormula, evaluate, not_forall, exists_prop, undag, unloadAndUndag]
          use w
          simp [modelCanSemImplyForm,vDash] at w_nP
          tauto
      rcases this with ⟨Γ, Γ_in, v_Γ, split⟩
      use Γ
      constructor
      · unfold loadDagNextTransRefl; rw [ftr.iff]; simp; tauto
      · exact ⟨v_Γ, split⟩

  case test ψ =>
    use (fs ++ [ψ], Sum.inr (~φ)) -- unique successor
    constructor
    · unfold loadDagNextTransRefl; rw [ftr.iff]; right; simp; rw [ftr.iff]; simp
    · constructor
      · intro f f_in
        simp at *
        cases f_in
        · apply v_D
          simp
          tauto
        · specialize v_D (~⌈?'ψ⌉unloadAndUndag φ)
          simp at v_D
          aesop
      · right; aesop
termination_by
  loadNotStarSoundnessAux α M v w fs φ v_D v_a_w w_nP => mOfProgram α

-- Note that the "Option" here is always "some", but we keep it for
-- compatibility with `inductive LoadRule` in LocalTableau.lean.
def loadDagEndNodes : LDDTNode → List (List Formula × Option NegLoadFormula)
  | (fs, (Sum.inl φ)) => [ (fs, some φ) ]
  | (fs, (Sum.inr df)) => ((loadDagNext (fs, Sum.inr df)).attach.map
      (fun ⟨gsdf, h⟩ =>
        have : mOfLoadDagNode gsdf < mOfLoadDagNode (fs, Sum.inr df) := mOfLoadDagNode.isDec h
        loadDagEndNodes gsdf)).join
termination_by
  loadDagEndNodes fs => mOfLoadDagNode fs
decreasing_by simp_wf; assumption

instance {W : Type} : vDash (KripkeModel W × W) (List Formula × Option NegLoadFormula) :=
  vDash.mk λ ⟨M,w⟩ (fs, mf) => ∀ φ ∈ fs ++ (mf.map (λ (~'lf) => ~unload lf)).toList, evaluate M w φ

theorem loadDagEnd_subset_next
    (O_in : Ω ∈ loadDagNext Γ) : loadDagEndNodes Ω ⊆ loadDagEndNodes Γ := by
  intro e
  rcases Γ with ⟨fs, mdf⟩
  rcases mdf with none | ⟨df⟩
  · simp [dagNext] at O_in
  · intro e_in
    unfold loadDagEndNodes loadDagNext
    aesop

theorem loadDagEndOfSome_iff_step : Γ ∈ loadDagEndNodes (fs, (Sum.inr (~⌊a⌋f))) ↔
    ∃ S ∈ loadDagNext (fs, Sum.inr (~⌊a⌋f)), Γ ∈ loadDagEndNodes S := by
  cases a
  all_goals (simp [loadDagEndNodes]; done)


theorem loadDagEnd_subset_trf {Ω Γ} :
    Ω ∈ loadDagNextTransRefl Γ → loadDagEndNodes Ω ⊆ loadDagEndNodes Γ := by
  intro O_in
  unfold loadDagNextTransRefl at O_in
  rw [ftr.iff] at O_in
  cases O_in
  · aesop
  case inr hyp =>
    rcases hyp with ⟨S, S_in, O_in⟩
    have := loadDagEnd_subset_next S_in
    have := loadDagEnd_subset_trf O_in
    tauto
termination_by
  loadDagEnd_subset_trf Ω Γ hyp  => mOfLoadDagNode Γ
decreasing_by simp_wf; apply mOfLoadDagNode.isDec; assumption

theorem loadDagNormal_is_loadDagEnd {Γ S : LDDTNode}
    (Γ_in : Γ ∈ loadDagNextTransRefl S)
    :
    (∀ χ, (Γ_normal : Γ.2 = (Sum.inl (~'χ))) → (⟨Γ.1, some (~'χ)⟩ ∈ loadDagEndNodes S))
    := by
    intro χ Γ_normal
    rcases Γ with ⟨fs,odf⟩
    have := loadDagEnd_subset_trf Γ_in
    apply this
    simp only [loadDagNextTransRefl] at *
    rw [Γ_normal]
    simp [loadDagEndNodes]

theorem loadNotStarSoundness
    (M : KripkeModel W) (w : W) (a : Program) (χ : LoadFormula)
    :
    (M, w) ⊨ negUnload (~'(⌊∗a⌋χ)) →
      ∃ Γ ∈ [(∅, some (~'χ))] ++ loadDagEndNodes (∅, Sum.inr (NegDagLoadFormula.neg (injectLoad a χ))),
        (M,w) ⊨ Γ :=
  by
  intro w_naSf
  simp [modelCanSemImplyForm] at w_naSf
  rcases w_naSf with ⟨y, x_rel_y, y_nf⟩
  cases starCases x_rel_y -- NOTE: Relation.ReflTransGen.cases_head without ≠ is not enough here ...
  case inl w_is_y =>
    subst w_is_y
    use (∅, some (~'χ))
    simp
    intro f f_in
    simp at *
    subst f_in
    simp only [evaluate]
    exact y_nf
  case inr hyp =>
    -- (... because we need to get the in-equality here to get the contradiction below.)
    rcases hyp with ⟨_, z, w_neq_z, w_a_z, z_aS_y⟩
    -- MB now distinguishes whether a is atomic, we don't care.
    have := loadNotStarSoundnessAux a M w z [] (DagLoadFormula.ldg a χ)
    specialize this _ w_a_z _
    · intro g g_in
      simp at g_in
      subst g_in
      simp
      exact ⟨z, ⟨w_a_z, ⟨y, ⟨z_aS_y, y_nf⟩⟩⟩⟩
    · simp [vDash,modelCanSemImplyForm]
      use y
    rcases this with ⟨Γ, Γ_in, w_Γ, caseOne | caseTwo⟩
    · rcases caseOne with ⟨A, as, Γ2def, _, Γ_normal⟩
      simp
      right
      use Γ.1, some (~'⌊·A⌋⌊⌊as⌋⌋undagOnly (DagLoadFormula.ldg a χ))
      constructor
      · have := loadDagNormal_is_loadDagEnd Γ_in _ (by tauto)
        aesop
      · intro f f_in
        simp at f_in
        cases f_in
        · aesop
        case inr f_def =>
          subst f_def
          rcases Γ with ⟨Γ1,Γ2⟩
          simp at Γ2def
          subst Γ2def
          apply w_Γ
          simp
    · absurd caseTwo.2 -- contradiction!
      exact w_neq_z

theorem loadNotStarInvertAux (M : KripkeModel W) (v : W) S :
    (∃ Γ ∈ loadDagNext S, (M, v) ⊨ Γ) → (M, v) ⊨ S := by
  intro hyp
  rcases hyp with ⟨Γ, Γ_in, v_Γ⟩
  unfold LDDTNode at S
  rcases S with ⟨fs, ⟨⟨lf⟩⟩ | ⟨⟨dlf⟩⟩⟩
  · simp only [loadDagNext, List.find?_nil, List.not_mem_nil] at Γ_in
  · cases dlf
    case box a dlf =>
      cases a
      all_goals (simp at Γ_in; try cases Γ_in; all_goals try subst Γ_in)
      all_goals (intro f f_in; simp at f_in)
      case atom_prog =>
        cases f_in
        · apply v_Γ; simp at *; tauto
        case inr hyp => subst hyp; apply v_Γ; simp
      case sequence a b =>
        cases f_in
        · apply v_Γ; simp at *; tauto
        case inr hyp => subst hyp; specialize v_Γ (~⌈a⌉⌈b⌉(unloadAndUndag dlf)); aesop
      case union.inl a b Γ_is =>
        cases f_in
        · apply v_Γ; simp at *; aesop
        case inr hyp => subst hyp; specialize v_Γ (~⌈a⌉(unloadAndUndag dlf)); aesop
      case union.inr a b Γ_is =>
        cases f_in
        · apply v_Γ; simp at *; aesop
        case inr hyp => subst hyp; specialize v_Γ (~⌈b⌉(unloadAndUndag dlf)); aesop
      case star.inl a Γ_is =>
        cases f_in
        · apply v_Γ; simp at *; aesop
        case inr hyp =>
          subst hyp; subst Γ_is; specialize v_Γ (~unloadAndUndag dlf); simp at *
          use v
      case star.inr a Γ_is =>
        cases f_in
        · apply v_Γ; subst Γ_is; simp at *; aesop
        case inr hyp =>
          subst hyp; subst Γ_is;
          specialize v_Γ (~⌈a⌉⌈∗a⌉(unloadAndUndag dlf))
          simp at *
          rcases v_Γ with ⟨x, v_a_x, y, x_aS_y, y_nf⟩
          use y
          exact ⟨Relation.ReflTransGen.head v_a_x x_aS_y, y_nf⟩
      case test.refl g =>
        cases f_in
        · apply v_Γ; simp at *; aesop
        case inr hyp =>
          subst hyp
          simp
          constructor
          · specialize v_Γ g; aesop
          · specialize v_Γ (~(unloadAndUndag dlf)); simp at v_Γ; aesop
    case dag => simp at Γ_in
    case ldg => simp at Γ_in

theorem loadNotStarInvert (M : KripkeModel W) (v : W) S
    :
    (∃ Γ ∈ loadDagEndNodes S, (M, v) ⊨ Γ) → (M, v) ⊨ S := by
  rintro ⟨Γ, Γ_in, v_Γ⟩
  rcases S_eq : S with ⟨fs, ⟨⟨lf⟩⟩ | ⟨⟨dlf⟩⟩⟩
  · subst S_eq
    simp [loadDagEndNodes] at Γ_in
    subst Γ_in
    exact v_Γ
  · subst S_eq
    cases df_eq : dlf
    case dag =>
      subst df_eq
      simp [loadDagEndNodes] at Γ_in
    case ldg =>
      subst df_eq
      simp [loadDagEndNodes] at Γ_in
    case box a f =>
      subst df_eq
      rw [loadDagEndOfSome_iff_step] at Γ_in
      rcases Γ_in with ⟨T, T_in, Γ_in⟩
      have v_T := loadNotStarInvert M v T ⟨Γ, ⟨Γ_in, v_Γ⟩⟩ -- recursion!
      exact loadNotStarInvertAux M v (fs , Sum.inr (~⌊a⌋f)) ⟨_, ⟨T_in, v_T⟩⟩
termination_by
  loadNotStarInvert M v S claim => mOfLoadDagNode S
decreasing_by simp_wf; apply mOfLoadDagNode.isDec; aesop

-- -- -- BOXES -- -- --

-- Here we need a List DagFormula, because of the ⋓ rule.
@[simp]
def BDNode := List Formula × List DagFormula

-- Dershowitz-Manna ordering for Lists
-- It is usually defined on multisets, but works for lists too because
-- count, i.e. number of occurrences, is invariant under permutation.

-- This is the standard definition ...
-- originally formalized in Lean 3 by Pedro Minicz
-- https://gist.github.com/b-mehta/ee89376db987b749bd5120a2180ce3df
@[simp]
def dm' (α) := List α
@[simp]
def to_dm' {α} (s : List α) : dm' α := s
@[simp]
instance {α : Type u} [DecidableEq α] [LT α] : LT (dm' α) :=
  { lt := λ M N =>
    ∃ (X Y : List α),
      X ≠ ∅
      ∧ (X : List α) ≤ (N : List α)
      ∧ M = (N.diff X) ++ Y
      ∧ ∀ y ∈ Y, ∃ x ∈ X, y < x }
--
-- ... but we use the alternative by Huet and Oppen:
@[simp]
def dm (α) := List α
@[simp]
def to_dm {α} (s : List α) : dm α := s
@[simp]
instance {α : Type u} [DecidableEq α] [LT α] : LT (dm α) :=
  { lt := λ M N =>  -- M < N iff ...
      M ≠ N
    ∧ ∀ ψ_y, -- for all y
      M.count ψ_y > N.count ψ_y → -- M(y) > N(y) implies there is an x > y
        ∃ ψ_x, ψ_y < ψ_x ∧ M.count ψ_x < N.count ψ_x } -- M(x) < N(x)

-- The standard result about the Dershowitz–Manna ordering.
-- Someone should get this into Mathlib.
theorem wf_dm {α : Type u} [DecidableEq α] [LT α]
    (t :  WellFoundedLT α) :
    WellFounded ((LT.lt) : dm α → dm α → Prop) := by
  apply WellFounded.intro
  intro dma
  apply Acc.intro dma
  intro dmb h
  cases h
  sorry

instance [DecidableEq α] [LT α] (t : WellFoundedLT α) : IsWellFounded (dm α) (LT.lt) := by
  constructor
  exact wf_dm t

-- Old defi
-- def mOfBoxDagNode : BDNode → ℕ
--   | ⟨_, []⟩ => 0
--   | ⟨_, dfs⟩ => 1 + (dfs.map mOfDagFormula).sum + (dfs.map mOfDagFormula).length

-- def sumofpower : ℕ -> List ℕ → ℕ
-- | _, []        => 0
-- | m, (n :: ns) => m ^ n + sumofpower m ns

-- helper function
def sumofpower :List ℕ → ℕ
| []        => 0
| n :: ns => 3 ^ n + sumofpower ns

-- New defi
-- Here n is the parameter of the measure.
-- def mOfBoxDagNode : BDNode → ℕ →  ℕ
--   | ⟨_, []⟩, _ => 0
--   | ⟨_, dfs⟩, n => sumofpower (n + 1) (dfs.map mOfDagFormula)

-- big measure
def mOfBoxDagNode : BDNode →  ℕ
  | ⟨fs, dfs⟩ => sumofpower (fs.map mOfFormula) + sumofpower (dfs.map mOfDagFormula)

-- Immediate sucessors of a node in a Daggered Tableau, for boxes.
-- Note that this is still fully deterministic.
@[simp]
def boxDagNext : BDNode → List BDNode
  | (fs, (⌈·A⌉φ)::rest) => [ (fs ++ [undag (⌈·A⌉φ)], rest) ]
  | (fs, (⌈α⋓β⌉φ)::rest) => [ (fs, (⌈α⌉φ)::(⌈β⌉φ)::rest ) ]
  | (fs, (⌈?'ψ⌉φ)::rest) => [ (fs ++ [~ψ], rest)
                            , (fs, φ::rest) ]
  | (fs, (⌈α;'β⌉φ)::rest) => [ (fs, (⌈α⌉⌈β⌉φ)::rest) ]
  | (fs, (⌈∗α⌉φ)::rest) => [ (fs, φ::(⌈α⌉⌈α†⌉(undag φ))::rest) ] -- NOT splitting!
  | (fs, (⌈_†⌉_)::rest) => [ (fs, rest) ] -- delete formula, but keep branch!
  | (_, []) => [ ] -- end node of dagger tableau

theorem boxDagNextDMisDec {Δ Γ : BDNode} (Γ_in : Γ ∈ boxDagNext Δ) :
    to_dm Γ.2 < to_dm Δ.2 := by
  rcases Δ with ⟨fs, _|⟨df,rest⟩⟩
  case nil =>
    exfalso
    simp at Γ_in
  case cons =>
    cases df
    case dag α φ =>
      simp at Γ_in
      subst Γ_in
      simp
      constructor
      · apply Ne.symm
        apply List.cons_ne_self
      · intro ψ_y countclaim
        exfalso
        rw [List.count_cons] at countclaim
        simp at countclaim
    case box a ψ =>
      cases a
      all_goals (simp at *; try subst Γ_in)
      case atom_prog A =>
        simp
        constructor
        · apply Ne.symm
          apply List.cons_ne_self
        · intro ψ_y countclaim
          simp [List.count_cons] at countclaim
      case sequence α β =>
        simp
        constructor
        · intro α_def
        -- use that α (or ψ) cannot contain itself
          exfalso
          exact ProgramSequenceNotSelfContaining α β α_def
        · intro ψ_y countclaim
          simp [List.count_cons] at countclaim
          have : ψ_y = ⌈α⌉⌈β⌉ψ := by
            -- sorry (fixed)-- use countclaim
            by_contra ne
            rw [← Ne.ite_eq_right_iff] at ne
            rw [ne] at countclaim
            aesop
            aesop
          subst this
          use ⌈α;'β⌉ψ
          simp [List.count_cons] at *
          constructor
          · linarith
          · tauto
      case union α β =>
        simp
        constructor
        · intro α_def
          -- use that α (or ψ) cannot contain itself
          exfalso
          exact ProgramUnionNotSelfContainingLeft α β α_def
        · intro ψ_y countclaim
          simp [List.count_cons] at countclaim
          have : (ψ_y = ⌈α⌉ψ) ∨ (ψ_y = ⌈β⌉ψ)  := by
            by_contra ndis
            have left: ¬ψ_y = ⌈α⌉ψ := by tauto
            have right: ¬ψ_y = ⌈β⌉ψ := by tauto
            rw [← Ne.ite_eq_right_iff] at left
            rw [left] at countclaim
            rw [← Ne.ite_eq_right_iff] at right
            rw [right] at countclaim
            . aesop
            . tauto
            . aesop
          cases this
          all_goals (rename_i h; subst h; use ⌈α ⋓ β⌉ψ; simp [List.count_cons] at *)
          · constructor
            · linarith
            · -- use non-self-containing and linarith
              have this1: ¬(α⋓β) = α := by exact ProgramUnionNotSelfContainingLeft' α β
              have this2: ¬(α⋓β) = β := by exact ProgramUnionNotSelfContainingRight' α β
              rw [← Ne.ite_eq_right_iff] at this1
              rw [this1]
              . rw [← Ne.ite_eq_right_iff] at this2
                rw [this2]
                linarith
                tauto
              . linarith
          · constructor
            · linarith
            · -- use non-self-containing and linarith
              have this1: ¬(α⋓β) = α := by exact ProgramUnionNotSelfContainingLeft' α β
              have this2: ¬(α⋓β) = β := by exact ProgramUnionNotSelfContainingRight' α β
              rw [← Ne.ite_eq_right_iff] at this1
              rw [this1]
              . rw [← Ne.ite_eq_right_iff] at this2
                rw [this2]
                linarith
                tauto
              . linarith
      case star α =>
        simp
        constructor
        · intro _
          apply List.cons_ne_self
        · intro ψ_y countclaim
          simp [List.count_cons] at countclaim
          have : (ψ_y = ψ) ∨ (ψ_y = ⌈α⌉⌈α†⌉(undag ψ)) := by
            by_contra ndis
            have left: ¬ (ψ_y = ψ) := by tauto
            have right: ¬ (ψ_y = ⌈α⌉⌈α†⌉(undag ψ)) := by tauto
            rw [← Ne.ite_eq_right_iff] at left
            rw [left] at countclaim
            rw [← Ne.ite_eq_right_iff] at right
            simp only [undag] at *
            rw [right] at countclaim
            absurd countclaim
            simp
            all_goals tauto
          cases this
          all_goals (rename_i h; use ⌈∗α⌉ψ; subst h; simp [List.count_cons] at *)
          · have : ¬ ((∗α) = α) := ProgramStarNotSelfContain α
            have : ¬ ((∗α) = α ∧ ψ_y = ⌈α†⌉undagDagFormula ψ_y) := by tauto
            rw [← Ne.ite_eq_right_iff] at this
            rw [this]
            have : ¬ ((⌈∗α⌉ψ_y) = ψ_y) := ProgramBoxStarNotSelfContain α ψ_y
            rw [← Ne.ite_eq_right_iff] at this
            rw [this]
            all_goals tauto
            aesop
          · constructor
            · linarith
            · have : ¬ ((∗α) = α) := ProgramStarNotSelfContain α
              have : ¬ ((∗α) = α ∧ ψ = ⌈α†⌉undagDagFormula ψ) := by tauto
              rw [← Ne.ite_eq_right_iff] at this
              rw [this]
              have : ¬ ((⌈∗α⌉ψ) = ψ) := ProgramBoxStarNotSelfContain α ψ
              rw [← Ne.ite_eq_right_iff] at this
              rw [this]
              all_goals tauto
              aesop
      case test f =>
        cases Γ_in
        all_goals (rename_i h; subst h; simp [List.count_cons] at *)
        · apply Ne.symm
          apply List.cons_ne_self
        · constructor
          · exact ProgramTestNotSelfContain ψ f
          · intro ψ_y countclaim
            have : ψ_y = ψ := by aesop
            subst this
            have : ¬ (ψ_y = ⌈?'f⌉ψ_y) := ProgramTestNotSelfContain ψ_y f
            use ⌈?'f⌉ψ_y
            simp
            all_goals tauto

-- idea: replace use of "ftr" below with a relation like this:
-- def boxDagNextRel : (List Formula × List DagFormula) → (List Formula × List DagFormula) → Prop :=
-- NICE: can then use more stuff from Mathlib?
-- BAD: List of successors no longer computable / easy to get?

@[simp]
def boxDagNextTransRefl : (List Formula × List DagFormula) → List (List Formula × List DagFormula) :=
  ftr boxDagNext sorry sorry -- TODO to_dm @mOfBoxDagNode.isDec
  -- ftr boxDagNext mOfBoxDagNode @mOfBoxDagNode.isDec

instance modelCanSemImplyBDNode {W : Type} : vDash (KripkeModel W × W) BDNode :=
  vDash.mk (λ ⟨M,w⟩ (fs, mf) => ∀ φ ∈ fs ++ (mf.map undag), evaluate M w φ)

def boxDagEndNodes : BDNode → List (List Formula)
  | (fs, []) => [ fs ]
  | (fs, df::rest) => ((boxDagNext (fs, df::rest)).attach.map
      (fun ⟨gsdf, h⟩ =>
        have := boxDagNextDMisDec h
        boxDagEndNodes gsdf)).join
termination_by
  boxDagEndNodes fs => to_dm fs.2
decreasing_by
  simp_wf;
  sorry -- goal is now "False", it seems we are picking up a wrong instance and not dm from above.

theorem boxDagEnd_subset_next
    (O_in : Ω ∈ boxDagNext Γ) : boxDagEndNodes Ω ⊆ boxDagEndNodes Γ := by
  intro e
  rcases Γ with ⟨fs, mdf⟩
  rcases mdf with none | ⟨df⟩
  · simp [dagNext] at O_in
  · intro e_in
    unfold boxDagEndNodes
    aesop

theorem boxDagEnd_subset_trf {Ω Γ} :
    Ω ∈ boxDagNextTransRefl Γ → boxDagEndNodes Ω ⊆ boxDagEndNodes Γ := by
  intro O_in
  unfold boxDagNextTransRefl at O_in
  rw [ftr.iff] at O_in
  cases O_in
  · aesop
  case inr hyp =>
    rcases hyp with ⟨S, S_in, O_in⟩
    have := boxDagEnd_subset_next S_in
    have := boxDagEnd_subset_trf O_in
    tauto
termination_by
  boxDagEnd_subset_trf Ω Γ hyp => to_dm Γ.2
decreasing_by simp_wf; sorry -- apply boxDagNextDMisDec; assumption


-- A normal successor in a box dagger tableau is an end node.
theorem boxDagNormal_is_dagEnd
    (Γ_in : Γ ∈ boxDagNextTransRefl S)
    (Γ_normal : Γ.2 = [])
    :
    (Γ.1 ∈ boxDagEndNodes S) := by
  have := boxDagEnd_subset_trf Γ_in
  apply this
  rcases Γ with ⟨fs,odf⟩
  subst Γ_normal
  simp [boxDagEndNodes]


-- IDEA: prove that boxDagEndNodesOf is independent under permutation of the list of dag formula!

theorem starInvertAux
    (M : KripkeModel W)
    (v : W)
    (αs : List Program)
    (β : Program)
    (φ : Formula) -- normal, not a dag!
    -- now we define a path in deterministic boxDagNext:
    (k : ℕ)
    (Γs : Vector BDNode (k.succ.succ))
    (_ : ∀ i : Fin n, (Γs.get i.castSucc) ∈ boxDagNext (Γs.get i.succ))
    (φ_in : φ ∈ (Γs.head.1)) -- what if it is the dagger form?
    -- still need to say [β†]φ is in Γ_k
    : (M, v) ⊨ undag (DagFormula.boxes αs (⌈β†⌉ φ)) :=
  by
  sorry


theorem boxDagEndOfSome_iff_step :
    Γ ∈ boxDagEndNodes (fs, (ψ : DagFormula) :: rest)
    ↔
    ∃ S ∈ boxDagNext (fs, (ψ : DagFormula) :: rest), Γ ∈ boxDagEndNodes S :=
  by
  sorry
  -- cases a
  -- all_goals (simp [boxDagEndNodes]; done)


theorem starInvert
     (M : KripkeModel W) (v : W) S
     : (∃ Γ ∈ boxDagEndNodes S, (M, v) ⊨ Γ) → (M, v) ⊨ S :=
  by
  rintro ⟨Γ, Γ_in, v_Γ⟩
  rcases S_eq : S with ⟨fs, dfs⟩ -- explicit hypotheses in rcases for termination, as in notStarInvert
  subst S_eq
  cases dfs -- : mdf
  case nil =>
    simp [boxDagEndNodes] at Γ_in
    subst Γ_in
    simp [modelCanSemImplyBDNode]
    exact v_Γ
  case cons ψ rest =>
    -- rcases ndf_eq : ndf with ⟨df⟩
    -- subst ndf_eq
    cases df_eq : ψ
    case dag α φ =>
      subst df_eq
      simp [boxDagEndNodes] at Γ_in -- this applies the dag rule!
      have v_fs_rest := starInvert M v (fs, rest) ⟨Γ, ⟨Γ_in, v_Γ⟩⟩ -- recursion!
      intro f f_in
      simp at f_in
      -- three cases
      cases f_in
      · apply v_fs_rest; simp; tauto
      case inr hyp =>
        cases hyp
        case inl f_def =>
          subst f_def
          -- now apply starInvertAux here
          sorry
        · apply v_fs_rest; simp; tauto
    case box α ψ =>
      subst df_eq
      -- rw [boxDagEndOfSome_iff_step] at Γ_in
      intro f f_in
      simp at *
      -- three cases again? or recursion for all?
      sorry
termination_by
  starInvert M v S claim => mOfBoxDagNode S
decreasing_by simp_wf; sorry -- apply mOfBoxDagNode.isDec; aesop

theorem starSoundnessAux {M : KripkeModel W} {v : W} {fs ψ dfs} :
    S = ⟨fs, ψ::dfs⟩ → (M, v) ⊨ S → (∃ Γ ∈ boxDagNext S, (M, v) ⊨ Γ) := by
  intro S_def v_S
  subst S_def
  simp at *
  cases ψ
  case dag =>
    use fs, dfs
    simp only [List.mem_singleton, true_and]
    intro f f_in
    apply v_S
    aesop
  case box α ψ =>
    cases α
    all_goals (simp; refine ⟨_,_,⟨⟨rfl,rfl⟩,?_⟩⟩)
    case atom_prog => intro f f_in; apply v_S; aesop
    case sequence β γ => intro f f_in; have := v_S (undag (⌈β;'γ⌉ψ)); aesop
    case union β γ => intro f f_in; have := v_S (undag (⌈β⋓γ⌉ψ)); aesop
    case star β =>
      intro f f_in
      have := v_S (undag (⌈∗β⌉ψ))
      simp at this
      simp at f_in
      rcases f_in with f_in_fs | f_is_ψ | f_is_bbψ | ⟨g, f_in_dfs⟩
      · apply v_S; simp; tauto
      · subst f_is_ψ; apply this v Relation.ReflTransGen.refl
      · subst f_is_bbψ
        simp only [evaluate, relate]
        intro w v_β_w u w_βS_u
        exact this u (Relation.ReflTransGen.head v_β_w w_βS_u)
      · specialize v_S f; aesop
    case test φ =>
      simp at *
      have := v_S (undag (⌈?'φ⌉ψ))
      simp at this
      cases em (evaluate M v φ)
      · use fs, ψ::dfs
        simp only [and_self, or_true, true_and]
        intro f f_in
        aesop
      · use fs ++ [~φ], dfs
        simp only [and_self, true_or, true_and]
        intro f f_in
        aesop

-- Soundness for the box star rule.
-- This Lemma was missing in Borzechowski.
theorem starSoundness (M : KripkeModel W) (v : W) S :
    (M, v) ⊨ S → ∃ Γ ∈ boxDagEndNodes S, (M, v) ⊨ Γ := by
  intro v_S
  rcases def_S : S with ⟨fs, nil | ⟨df,rest⟩⟩
  · simp [boxDagEndNodes]; aesop
  · cases df
    case dag α φ =>
      simp [boxDagEndNodes]
      have : mOfBoxDagNode (fs, rest) < mOfBoxDagNode S := by sorry -- apply mOfBoxDagNode.isDec; aesop
      apply starSoundness
      intro f
      aesop
    case box α ψ =>
      rcases starSoundnessAux def_S v_S with ⟨T, T_in, v_T⟩
      have : mOfBoxDagNode T < mOfBoxDagNode S := by sorry -- apply mOfBoxDagNode.isDec; aesop
      rcases starSoundness M v T v_T with ⟨Γ, Γ_in, v_Γ⟩
      refine ⟨Γ, ?_, v_Γ⟩
      subst def_S
      exact boxDagEnd_subset_next T_in Γ_in
termination_by
  starSoundness _ _ _ S _ => mOfBoxDagNode S
