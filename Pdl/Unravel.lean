import Mathlib.Data.Finset.Basic

import Pdl.Syntax
import Pdl.Discon
import Pdl.Semantics

-- UNRAVELING
-- | New Definition 10
@[simp]
def unravel : Formula → List (List Formula)
  -- diamonds: ⋓
  | ~⌈·a⌉P => [[~⌈·a⌉P]]
  | ~⌈a ⋓ b⌉P => unravel (~⌈a⌉P) ∪ unravel (~⌈b⌉P)
  | ~⌈✓ Q⌉P => [[Q]] ⊎ unravel (~P)
  | ~⌈a;b⌉P => unravel (~⌈a⌉⌈b⌉P)
  | ~†_ => ∅
  | ~⌈∗a⌉P => {{~P}} ∪ unravel (~⌈a⌉(†⌈∗a⌉P)) -- TODO omit {{~P}} if P contains dagger
  -- boxes:
  | ⌈·a⌉P => [[⌈·a⌉ P]]
  | ⌈a ⋓ b⌉ P => unravel (⌈a⌉P) ⊎ unravel (⌈b⌉P)
  | ⌈✓ Q⌉P => [[~Q]] ∪ unravel P
  | ⌈a;b⌉P => unravel (⌈a⌉⌈b⌉P)
  | †P => {∅}
  | ⌈∗a⌉P => {{P}} ⊎ unravel (⌈a⌉(†⌈∗a⌉P)) -- TODO omit {{P}} when P contains dagger
  -- all other formulas we do nothing, but let's pattern match them all.
  | ·c => [[·c]]
  | ~·c => [[~·c]]
  | ~⊥ => [[~⊥]]
  | ⊥ => [[⊥]]
  | ~~f => [[~~f]]
  | f⋀g => [[f⋀g]]
  | ~f⋀g => [[~f⋀g]]
termination_by
  unravel f => mOfFormula f

@[simp]
def nsub : Formula → List Formula
  -- diamonds:
  | ~⌈_⌉ P => nsub P
  | ~†P => [~P]
  | †P => [P]
  -- boxes:
  | ⌈_⌉P => nsub P
  -- all other formulas:
  | ·_ => ∅
  | ~·_ => ∅
  | ~⊥ => ∅
  | ⊥ => ∅
  | ~~f => nsub f
  | f⋀g => nsub f ++ nsub g
  | ~f⋀g => nsub f ++ nsub g

theorem rel_steps_last {as} : ∀ v w,
  relate M (Program.steps (as ++ [a])) v w ↔
    ∃ mid, relate M (Program.steps as) v mid ∧ relate M a mid w :=
  by
  induction as
  case nil =>
    simp at *
  case cons a2 as IH =>
    intro s t
    simp at *
    constructor
    · intro lhs
      rcases lhs with ⟨next, s_a2_next, next_asa_t⟩
      rw [IH] at next_asa_t
      tauto
    · intro rhs
      rcases rhs with ⟨m,⟨y,yP,yP2⟩,mP⟩
      use y
      rw [IH]
      tauto

-- Like Lemma 4 from Borzechowski, but using "unravel" instead of a local tableau with n-nodes.
-- see https://malv.in/2020/borzechowski-pdl/Borzechowski1988-PDL-translation-Gattinger2020.pdf#lemma.4
-- TODO: maybe simplify by not having a context X' here / still as useful for showing soundness of ~* rule?
-- TODO: analogous lemma for the box case? and * rule?
-- TODO: rename to:
-- - diamondStarSound <<<
-- - diamondStarInvert
-- - boxStarSound
-- - boxStarInvert
-- and more?

theorem likeLemmaFour :
  ∀ M (a : Program) (w v : W) (X' : List Formula) (P : Formula),
    w ≠ v →
      (M, w) ⊨ (X' ++ [~⌈a⌉P]) → relate M a w v → (M, v)⊨(~P) →
        ∃ Y ∈ {X'} ⊎ unravel (~⌈a⌉P), (M, w)⊨Y
          ∧ ∃ as : List Program, (~ Formula.boxes as P) ∈ Y
            ∧ relate M (Program.steps as) w v :=
  by
  intro M a
  -- no 'induction', but using recursive calls instead
  cases a
  case atom_prog A =>
    intro w v X' P w_neq_v w_sat_X w_a_v v_sat_nP
    use X' ++ [(~⌈·A⌉P)] -- "The claim holds with Y = X" says MB.
    unfold unravel
    simp
    constructor
    · assumption
    · use [·A]
      unfold Formula.boxes
      simp at *
      exact w_a_v
  case sequence b c =>
    intro w v X' P w_neq_v w_sat_X w_bc_v v_sat_nP
    unfold relate at w_bc_v
    rcases w_bc_v with ⟨u, w_b_u, u_c_v⟩
    have IHb := likeLemmaFour M b w u X' -- get IH using a recursive call
    specialize IHb (⌈c⌉ P) _ _ w_b_u _
    · sorry -- need w ≠ u here?
    · intro f lhs
      simp at lhs
      cases' lhs with f_in_X other
      · apply w_sat_X f
        simp
        left
        exact f_in_X
      · simp at other
        specialize w_sat_X (~⌈b;c⌉P)
        subst other
        specialize w_sat_X _
        · simp
        simp at *
        rcases w_sat_X with ⟨x,y,y_c_x,w_b_y,nP⟩
        use y
        tauto
    · unfold vDash.SemImplies at *
      unfold modelCanSemImplyForm at *
      simp at *
      use v
    rcases IHb with ⟨Y, Y_in, w_conY, as, nBascP_in_Y, w_as_u⟩
    use Y
    constructor
    · simp at *
      exact Y_in
    constructor
    · tauto
    · use as ++ [c]
      cases as
      case nil => -- n = 0, MB says we need IH again?
        simp at *
        rw [w_as_u]
        exact ⟨nBascP_in_Y,u_c_v⟩
      case cons a as => -- n > 0 in MB
        simp at *
        constructor
        · rw [boxes_last]
          exact nBascP_in_Y
        · rcases w_as_u with ⟨t, w_a_t, y_as_u⟩
          use t
          constructor
          · exact w_a_t
          · rw [rel_steps_last]
            use u
  case union a b =>
    intro w v X' P w_neq_v w_sat_X w_aub_v v_sat_nP
    unfold relate at w_aub_v
    cases w_aub_v
    case inl w_a_v =>
      have IH := likeLemmaFour M a w v X'
      specialize IH P w_neq_v _ w_a_v _
      · unfold vDash.SemImplies at *
        unfold modelCanSemImplyList at *
        unfold modelCanSemImplyForm at *
        simp at *
        intro f f_in
        cases f_in
        case inl f_in_X' =>
          apply w_sat_X f
          left
          exact f_in_X'
        case inr f_is_naP =>
          subst f_is_naP
          simp
          use v
      · exact v_sat_nP
      rcases IH with ⟨Y, Y_in, w_conY, as, nBasP_in_Y, w_as_v⟩
      use Y
      constructor
      · simp at *
        rcases Y_in with ⟨Z, Z_in, Ydef⟩
        use Z
        tauto
      · constructor
        · exact w_conY
        · use as
    case inr w_b_v =>
      have IH := likeLemmaFour M b w v X' P
      specialize IH w_neq_v _ w_b_v _
      · unfold vDash.SemImplies at *
        unfold modelCanSemImplyList at *
        unfold modelCanSemImplyForm at *
        simp at *
        intro f f_in
        cases f_in
        case inl f_in_X' =>
          apply w_sat_X f
          left
          exact f_in_X'
        case inr f_is_nbP =>
          subst f_is_nbP
          simp
          use v
      · exact v_sat_nP
      rcases IH with ⟨Y, Y_in, w_conY, as, nBasP_in_Y, w_as_v⟩
      use Y
      constructor
      · simp at *
        rcases Y_in with ⟨Z, Z_in, Ydef⟩
        use Z
        tauto
      · constructor
        · exact w_conY
        · use as
  case star a =>
    intro w v X' P w_neq_v w_sat_X w_aS_v v_sat_nP
    unfold relate at w_aS_v
    cases w_aS_v
    case refl =>
      absurd w_neq_v
      rfl
    case step u w_a_u u_aS_v =>
      -- idea: use starCases here?
      have IHa := likeLemmaFour M a w u X'
      specialize IHa (⌈∗a⌉P) _ _ w_a_u _
      · sorry
      · sorry
      · sorry
      rcases IHa with ⟨Y, Y_in, w_conY, as, nBasaSP_in_Y, w_as_u⟩
      use Y
      constructor
      · -- mismatch:  unravel (~⌈a⌉⌈∗a⌉P)  vs.  unravel (~⌈∗a⌉P)  :-(
        simp
        simp [unravel] at Y_in
        sorry
      · constructor
        · assumption
        · use (as ++ [∗a])
          constructor
          · -- use boxes_last or something similar?
            sorry
          · rw [rel_steps_last]
            use u
            constructor
            · assumption
            · simp
              assumption
  case test f =>
    intro w v X' P w_neq_v w_sat_X w_tf_v v_sat_nP
    unfold relate at w_tf_v
    rcases w_tf_v with ⟨w_is_v, w_f⟩
    subst w_is_v
    absurd w_neq_v
    rfl
