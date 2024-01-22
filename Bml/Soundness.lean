-- SOUNDNESS

import Bml.Syntax
import Bml.Tableau

open Classical

-- attribute [local instance 10] prop_decidable -- delete me?

open HasSat

-- Combine a collection of pointed models with one new world using the given valuation.
-- TODO: rewrite to term mode?
def combinedModel {β : Type} (collection : β → Σ W : Type, KripkeModel W × W)
    (newVal : Char → Prop) :
    KripkeModel (Sum Unit (Σ k : β, (collection k).fst)) × Sum Unit (Σ k : β, (collection k).fst) :=
  by
  constructor
  constructor
  · -- making the valuation function:
    intro world
    cases world
    case inl newWorld => -- the one new world
      cases newWorld
      exact newVal -- use new given valuation here!!
    case inr oldWorld => -- world in one of the given models:
      cases' oldWorld with R w
      exact (collection R).snd.fst.val w
  · -- defining relations:
    intro worldOne worldTwo
    cases worldOne <;> cases worldTwo -- four cases about two new or old worlds
    case inl.inl => exact False -- no reflexive loop at the new world.
    case inl.inr newWorld oldWorld =>
      exact HEq oldWorld.snd (collection oldWorld.fst).snd.snd -- conect new world to given points.
    case inr.inl => exact False -- no connection from models to new world
    case inr.inr oldWorldOne oldWorldTwo =>
      -- connect two old worlds iff they are from the same model and were connected there already:
      cases' oldWorldOne with kOne wOne
      cases' oldWorldTwo with kTwo wTwo
      have help : kOne = kTwo → Prop := by
        intro same
        have sameCol : collection kOne = collection kTwo := by rw [← same]
        rw [← sameCol] at wTwo
        exact (collection kOne).snd.fst.Rel wOne wTwo
      exact dite (kOne = kTwo) (fun same => help same) fun _ => False
  · -- point at the new world:
    left
    exact ()



-- The combined model preserves all truths at the old worlds.
theorem combMo_preserves_truth_at_oldWOrld {β : Type}
    (collection : β → Σ W : Type, KripkeModel W × W) (newVal : Char → Prop) :
    ∀ (f : Formula) (R : β) (oldWorld : (collection R).fst),
      Evaluate ((combinedModel collection newVal).fst, Sum.inr ⟨R, oldWorld⟩) f ↔
        Evaluate ((collection R).snd.fst, oldWorld) f :=
  by
  intro f
  induction f <;> intro R oldWorld
  case bottom => aesop
  case atom_prop c =>
    unfold combinedModel
    simp
  case neg f f_IH =>
    unfold Evaluate
    rw [f_IH R oldWorld]
  case And f g f_IH g_IH =>
    unfold Evaluate
    rw [f_IH R oldWorld]
    rw [g_IH R oldWorld]
  case box f f_IH =>
    unfold Evaluate
    constructor
    · intro true_in_combo
      intro otherWorld rel_in_old_model
      specialize f_IH R otherWorld
      rw [← f_IH]
      specialize true_in_combo (Sum.inr ⟨R, otherWorld⟩)
      apply true_in_combo
      unfold combinedModel
      simp
      exact rel_in_old_model
    · intro true_in_old
      simp
      constructor
      · intro newWorld
        unfold combinedModel
        tauto
      -- the new world is never reachable, trivial case
      · intro otherR otherWorld
        intro rel_in_new_model
        specialize f_IH otherR otherWorld
        unfold combinedModel at rel_in_new_model
        have sameR : R = otherR := by
          by_contra
          aesop
        subst sameR
        rw [f_IH]
        apply true_in_old
        -- remains to show that related in old model
        simp at *
        exact rel_in_new_model


-- The combined model for X satisfies X.
theorem combMo_sat_LR {L R : Finset Formula} {β : Set Formula}
    {beta_def : β = {F : Formula | f_in_TNode (~F.box) (L, R)}} (simple_LR : Simple (L, R)) (not_closed_LR : ¬Closed (L ∪ R))
    (collection : β → Σ W : Type, KripkeModel W × W)
    (all_pro_sat :
      ∀ F : β,
        ∀ f, (f ∈ (projection (L ∪ R) ∪ {~F})) → Evaluate ((collection F).snd.fst, (collection F).snd.snd) f) :
    ∀ f, f_in_TNode f (L, R)
      → Evaluate
        ((combinedModel collection fun c => Formula.atom_prop c ∈ (L ∪ R)).fst,
          (combinedModel collection fun c => Formula.atom_prop c ∈ (L ∪ R)).snd)
        f :=
  by
  intro f f_in_LR
  unfold Simple SimpleForm at simple_LR
  simp at simple_LR
  simp at f_in_LR
  rw [←Finset.mem_union] at f_in_LR
  cases f
  -- no induction because X is simple
  case bottom =>
    unfold Closed at not_closed_LR
    aesop
  case atom_prop =>
    unfold combinedModel
    unfold Evaluate
    aesop
  case
    neg f =>
    -- subcases :-/
    cases f
    case atom_prop =>
      unfold combinedModel
      unfold Evaluate
      unfold Closed at not_closed_LR
      rw [not_or] at not_closed_LR
      aesop
    case box f =>
      -- set coMo := ,
      simp only [Evaluate, not_forall]
      -- need reachable world with ~f, use the β-witness
      let h : f ∈ β := by rw [beta_def]; use f_in_LR
      let oldWorld : Sum Unit (Σ k : β, (collection k).fst) :=
        Sum.inr ⟨⟨f, h⟩, (collection ⟨f, h⟩).snd.snd⟩
      use oldWorld
      constructor
      · -- show that f is false at old world
        have coMoLemma :=
          combMo_preserves_truth_at_oldWOrld collection (fun c : Char => (·c) ∈ (L ∪ R)) f ⟨f, h⟩
            (collection ⟨f, h⟩).snd.snd
        rw [coMoLemma]
        specialize all_pro_sat ⟨f, h⟩ (~f)
        unfold Evaluate at all_pro_sat
        simp at *
        exact all_pro_sat
      ·-- show that worlds are related in combined model (def above, case 2)
        unfold combinedModel;
        simp
    case bottom => tauto
    case neg f =>
      rw [Finset.mem_union] at f_in_LR
      specialize simple_LR (~~f) f_in_LR
      simp at simple_LR
    case And f g =>
      rw [Finset.mem_union] at f_in_LR
      specialize simple_LR (~(f⋀g)) f_in_LR
      simp at simple_LR
  case And fa fb =>
    rw [Finset.mem_union] at f_in_LR
    specialize simple_LR (fa⋀fb) f_in_LR
    simp at simple_LR
  case box f =>
    unfold Evaluate
    intro otherWorld is_rel
    cases otherWorld
    · cases is_rel
    case inr otherWorld => -- otherWorld cannot be the (unreachable) new world
      have coMoLemma :=
        combMo_preserves_truth_at_oldWOrld collection (fun c => (·c) ∈ (L ∪ R)) f otherWorld.fst
          otherWorld.snd
      rw [coMoLemma]
      specialize all_pro_sat otherWorld.fst f
      simp at all_pro_sat
      rw [or_imp] at all_pro_sat
      cases' all_pro_sat with all_pro_sat_left all_pro_sat_right
      rw [←proj] at f_in_LR
      simp at *
      specialize all_pro_sat_right f_in_LR
      have sameWorld : otherWorld.snd = (collection otherWorld.fst).snd.snd := by
        rw [heq_iff_eq.mp (HEq.symm is_rel)]
      rw [sameWorld]
      simp
      exact all_pro_sat_right

-- Lemma 1 (page 16)
-- A simple set of formulas X is satisfiable if and only if
-- it is not closed  and  for all ¬[A]R ∈ X also XA; ¬R is satisfiable.
theorem Lemma1_simple_sat_iff_all_projections_sat {LR : TNode} :
    Simple LR → (Satisfiable LR ↔ ¬Closed (LR.1 ∪ LR.2) ∧ ∀ F, f_in_TNode (~(□F)) LR → Satisfiable (projection (LR.1 ∪ LR.2) ∪ {~F})) :=
  by
  intro LR_is_simple
  constructor
  · -- left to right
    intro sat_LR
    unfold Satisfiable at *
    rcases sat_LR with ⟨W, M, w, w_sat_LR⟩
    constructor
    · -- show that X is not closed:
      by_contra hyp
      unfold Closed at hyp
      cases' hyp with bot_in_LR f_and_notf_in_LR
      · exact w_sat_LR ⊥ bot_in_LR
      · rcases f_and_notf_in_LR with ⟨f, f_in_LR, notf_in_LR⟩
        let w_sat_f := w_sat_LR f f_in_LR
        let w_sat_notf := w_sat_LR (~f) notf_in_LR
        exact absurd w_sat_f w_sat_notf
    · -- show that for each ~[]R ∈ X the projection with ~R is satisfiable:
      intro R notboxr_in_LR
      let w_sat_notboxr := w_sat_LR (~(□R)) notboxr_in_LR
      unfold Evaluate at w_sat_notboxr
      simp at w_sat_notboxr
      rcases w_sat_notboxr with ⟨v, w_rel_v, v_sat_notr⟩
      use W, M, v
      intro g
      simp at *
      rw [or_imp]
      constructor
      · intro g_is_notR
        rw [g_is_notR]
        exact v_sat_notr
      · intro boxg_in_LR
        rw [proj] at boxg_in_LR
        rw [Finset.mem_union]at boxg_in_LR
        specialize w_sat_LR (□g) boxg_in_LR
        unfold Evaluate at w_sat_LR
        exact w_sat_LR v w_rel_v
  · -- right to left
    intro rhs
    cases' rhs with not_closed_LR all_pro_sat
    unfold Satisfiable at *
    -- Let's build a new Kripke model!
    let (L, R) := LR
    let β := {F : Formula | f_in_TNode (~(□F)) (L, R)}
    -- beware, using Axioms of Choice here!
    choose typeFor this_pro_sat using all_pro_sat
    choose modelFor this_pro_sat using this_pro_sat
    choose worldFor this_pro_sat using this_pro_sat
    -- define the collection:
    let collection : β → Σ W : Type, KripkeModel W × W :=
      by
      intro k
      cases' k with R notboxr_in_LR
      use typeFor R notboxr_in_LR, modelFor R notboxr_in_LR, worldFor R notboxr_in_LR
    let newVal c := f_in_TNode (Formula.atom_prop c) (L, R)
    let BigM := combinedModel collection newVal
    use Sum Unit (Σ k : β, (collection k).fst)
    use BigM.fst, BigM.snd
    -- apply Lemma, missing last argument "all_pro_sat"
    -- we need to use that X_is_simple (to restrict cases what phi can be)
    -- and that X is not closed (to ensure that it is locally consistent)
    apply combMo_sat_LR LR_is_simple not_closed_LR collection
    -- it remains to show that the new big model satisfies X
    intro R f f_inpro_or_notr
    cases' R with R notrbox_in_LR
    simp only [Finset.mem_union, Finset.mem_insert, Finset.mem_singleton, Subtype.coe_mk] at *
    specialize this_pro_sat R notrbox_in_LR
    cases' f_inpro_or_notr with f_inpro f_is_notboxR
    · -- if f is in the projection
      specialize this_pro_sat f
      rw [or_imp] at this_pro_sat
      cases' this_pro_sat with this_pro_sat_l this_pro_sat_r
      exact this_pro_sat_l f_inpro
    · -- case where f is ~[]R
      cases f_is_notboxR
      case refl =>
        specialize this_pro_sat (~R)
        rw [or_imp] at this_pro_sat
        cases' this_pro_sat with this_pro_sat_l this_pro_sat_r
        tauto
    simp


-- to check β
-- Each rule is sound and preserves satisfiability "downwards"
-- theorem localRuleSoundness {α : Finset Formula} {B : Finset (Finset Formula)} :
--  LocalRule α B → Satisfiable α → ∃ β ∈ B, Satisfiable β :=
theorem localRuleSoundness (rule : LocalRule (Lcond, Rcond) ress) :
  Satisfiable (Lcond ∪ Rcond) → ∃res ∈ ress, Satisfiable (res.1 ∪ res.2) :=
  by
    intro sat
    unfold Satisfiable at sat
    rcases sat with ⟨W, M, w, w_sat_LR⟩
    cases rule <;>
    ( try
      ( rename_i lr
        cases lr
        <;> simp at *
        <;> try (use W; use M; use w)
        case ncon φ ψ =>
          rw [imp_iff_not_or] at w_sat_LR
          cases' w_sat_LR with case_phi case_psi
          · apply Or.inl
            use W; use M; use w
          · apply Or.inr
            use W; use M; use w))
    all_goals aesop


lemma rule_implies_child_sat
  {ruleApp : LocalRuleApp (L, R) C}
  {rule : LocalRule (Lcond, Rcond) ress} :
  Satisfiable (L ∪ R) → ∃res ∈ ress, Satisfiable ((L \ Lcond ∪ res.1) ∪ (R \ Rcond ∪ res.2)) :=
  by
    intro satLR
    let ⟨ress, Lcond, Rcond, rule, prepf⟩ := ruleApp
    have satCond : Satisfiable (Lcond ∪ Rcond) :=
      subsetSat satLR (Finset.union_subset_union prepf.left prepf.right)
    have satRes : ∃res ∈ ress, Satisfiable (res.1 ∪ res.2) :=
      localRuleSoundness rule satCond
    sorry


lemma oneSidedRule_implies_child_sat_L_old
  {ruleApp : LocalRuleApp (L, R) C}
  (def_ruleA : ruleApp = (@LocalRuleApp.mk L R C (List.map (fun res => (res, ∅)) _) _ _ rule hC preproof))
  (rule_is_left : rule = LocalRule.oneSidedL orule )
  : Satisfiable (L ∪ X) → ∃c ∈ C.attach, Satisfiable (c.1.1 ∪ X) :=
  by
    intro LX_sat
    cases rule_is_left
    cases hC
    sorry


lemma oneSidedRule_implies_child_sat_R
  {ruleApp : LocalRuleApp (L, R) C}
  (def_ruleA : ruleApp = (@LocalRuleApp.mk L R C (List.map (fun res => (∅, res)) _) _ _ rule hC preproof))
  (rule_is_right : rule = LocalRule.oneSidedR orule )
  : Satisfiable (R ∪ X) → ∃c ∈ C.attach, Satisfiable (c.1.2 ∪ X) := sorry


-- The critical rule is sound and preserves satisfiability "downwards".
-- NOTE: This is stronger than Lemma 1, but we do not need.
theorem atmSoundness {LR : TNode} {f} (not_box_f_in_LR : f_in_TNode (~(□f)) LR) :
    Satisfiable LR → Satisfiable (projection (LR.1 ∪ LR.2) ∪ {~f}) :=
  by
  intro satLR
  unfold Satisfiable at satLR
  rcases satLR with ⟨W, M, w, w_sat_LR⟩
  constructor
  simp
  -- get the other reachable world:
  let w_sat_not_box_f := w_sat_LR (~f.box) not_box_f_in_LR
  unfold Evaluate at w_sat_not_box_f
  simp at w_sat_not_box_f
  rcases w_sat_not_box_f with ⟨v, w_rel_v, v_not_sat_f⟩
  -- show that the projection is satisfiable:
  use M, v
  constructor
  · exact v_not_sat_f
  intro phi phi_in_proj
  rw [proj] at phi_in_proj
  · specialize w_sat_LR phi.box _
    exact phi_in_proj
    unfold Evaluate at w_sat_LR
    exact w_sat_LR v w_rel_v


theorem localTableauAndEndNodesUnsatThenNotSat {LR : TNode} (ltLR : LocalTableau LR) :
    (∀Y, Y ∈ endNodesOf ⟨LR, ltLR⟩ → ¬Satisfiable Y) → ¬Satisfiable LR :=
  by
  intro endsOfLRnotSat
  rcases ltLR with ⟨lrApp, next⟩
  rename_i R; rename_i L
  case fromRule C =>
    by_contra satLR
    rcases lrApp with ⟨ress, Lcond, Rcond, rule, preproofL, preproofR⟩
    have prepf : Lcond ⊆ L ∧ Rcond ⊆ R := And.intro preproofL preproofR
    rename_i hC
    have satCond : Satisfiable (Lcond ∪ Rcond) :=
      subsetSat satLR (Finset.union_subset_union preproofL preproofR)
    rcases localRuleSoundness rule satCond with ⟨res, res_in_ress, satRes⟩
    have c_child : ∃c ∈ C, (L \ Lcond ∪ res.1, R \ Rcond ∪ res.2) = c :=
      by aesop
    cases' c_child with c hc
    set ltc := next c (hc.left)
    set LR : TNode := (L, R)
    set ltLR := LocalTableau LR
    have endNodesInclusion :
      ∀ Z, Z ∈ endNodesOf ⟨c, ltc⟩
      → Z ∈ endNodesOf ⟨LR, LocalTableau.fromRule
            (AppLocalTableau.mk (@LocalRuleApp.mk L R C ress Lcond Rcond rule hC prepf) next)⟩ :=
      by
        simp
        intro Z Z_endOF_c
        use endNodesOf ⟨c, ltc⟩
        tauto
    have endsOfcnotSat : ∀Z1, Z1 ∈ endNodesOf ⟨c, ltc⟩ → ¬Satisfiable Z1 :=
      by intro Z1 Z1_is_endOf_c; apply endsOfLRnotSat Z1 (endNodesInclusion Z1 Z1_is_endOf_c)
    have : (∀Z, Z ∈ endNodesOf ⟨c , ltc⟩ → ¬Satisfiable Z) → ¬Satisfiable c :=
      by
        have := localRuleAppDecreasesLength (@LocalRuleApp.mk L R C ress Lcond Rcond rule hC prepf) c hc.left -- for termination
        apply localTableauAndEndNodesUnsatThenNotSat ltc
    have cNotSat : ¬Satisfiable c := this endsOfcnotSat
    have cSat : Satisfiable c :=
      sorry  -- here we need the lemmas above that node sat -> child sat
    exact cNotSat cSat
  case fromSimple hSimple =>
    apply endsOfLRnotSat
    simp
termination_by
  localTableauAndEndNodesUnsatThenNotSat ltLR  => lengthOfTNode LR

-- uses slightly different syntax in ClosedTableau def
theorem tableauThenNotSat : ∀LR, ClosedTableau LR → ¬Satisfiable LR :=
  by
  intro LR ct
  let ⟨L, R⟩ := LR
  cases ct
  case loc Y apptab IH =>
    apply localTableauAndEndNodesUnsatThenNotSat (LocalTableau.fromRule apptab)
    intro Z ZisEndOfY
    have ZClosed : ClosedTableau Z := IH Z ZisEndOfY
    simp
    sorry
  case atmL φ notBoxPhiInY Y_is_simple ltProYnPhi =>
    rw [Lemma1_simple_sat_iff_all_projections_sat Y_is_simple]
    intro notClosedLR
    cases' notClosedLR with notClosed boxInTNodeThenSatProj
    specialize boxInTNodeThenSatProj φ
    have satProj : Satisfiable (projection ((L, R).1 ∪ (L, R).2) ∪ {~φ}) :=
      boxInTNodeThenSatProj (by aesop)
    simp [diamondProjectTNode] at ltProYnPhi
    sorry
  case atmR φ notBoxPhiInY Y_is_simple ltProYnPhi => sorry


-- Theorem 2, page 30
theorem correctness : ∀LR : TNode, Satisfiable LR → Consistent LR :=
  by
    intro LR
    contrapose
    unfold Consistent
    unfold Inconsistent
    simp only [not_nonempty_iff, not_isEmpty_iff, not_exists, not_forall, exists_prop, Nonempty.forall]
    intro hyp
    apply tableauThenNotSat LR hyp

theorem soundTableau : ∀φ, Provable φ → ¬Satisfiable ({~φ} : Finset Formula) :=
  by
    intro phi prov
    cases' prov with tabl
    exact tableauThenNotSat ({~phi}, ∅) tabl

theorem soundness : ∀φ, Provable φ → Tautology φ :=
  by
    intro φ prov
    apply notsatisfnotThenTaut
    rw [← singletonSat_iff_sat]
    apply soundTableau
    exact prov
