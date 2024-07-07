-- TABLEAU

import Mathlib.Data.List.ReduceOption

import Pdl.LocalTableau

open HasLength

-- PROJECTIONS

@[simp]
def formProjection : Nat → Formula → Option Formula
  | A, ⌈·B⌉φ => if A == B then some φ else none
  | _, _ => none

def projection : Nat → List Formula → List Formula
  | A, X => (X.map fun x => (formProjection A x)).reduceOption

@[simp]
theorem proj : g ∈ projection A X ↔ (⌈·A⌉g) ∈ X :=
  by
  induction X
  case nil =>
    simp only [projection, formProjection, beq_iff_eq, List.map_nil, List.not_mem_nil, iff_false]
    exact List.count_eq_zero.mp rfl
  case cons =>
    simp only [projection, formProjection, beq_iff_eq, List.map_cons, List.mem_cons]
    rw [List.reduceOption_mem_iff]
    aesop

/-! ## Loading and Loaded Histories -/

def boxesOf : Formula → List Program × Formula
| (Formula.box prog nextf) => let (rest,endf) := boxesOf nextf; ⟨prog::rest, endf⟩
| f => ([], f)

/-- A history is a list of TNodes.
This only tracks "big" steps, hoping we do not need steps within a local tableau.
The head of the first list is the newest TNode. -/
abbrev History : Type := List TNode

/-- A lpr means we can go `k` steps back in the history to
reach an equal node, and all nodes on the way are loaded. -/
def LoadedPathRepeat (Hist : History) (X : TNode) : Type :=
  Subtype (fun k => (Hist.get k).setEqTo X ∧ ∀ m ≤ k, (Hist.get m).isLoaded)

theorem LoadedPathRepeat_isLoaded (lpr : LoadedPathRepeat Hist X) : X.isLoaded := by
  rcases lpr with ⟨k, claim⟩
  have := setEqTo_isLoaded_iff claim.1
  rw [← this]
  apply claim.2
  apply le_refl

/-! ## The PDL rules -/

/-- A rule to go from Γ to Δ. Note the four variants of the modal rule. -/
inductive PdlRule : (Γ : TNode) → (Δ : TNode) → Type
  -- The (L+) rule:
  | loadL : (~⌈⌈δ⌉⌉⌈α⌉φ) ∈ L → PdlRule (L, R, none)
                                       (L.erase (~⌈⌈δ⌉⌉φ), R, some (Sum.inl (~'(⌊⌊δ⌋⌋⌊α⌋φ))))
  | loadR : (~⌈⌈δ⌉⌉⌈α⌉φ) ∈ R → PdlRule (L, R, none)
                                       (L, R.erase (~⌈⌈δ⌉⌉φ), some (Sum.inr (~'(⌊⌊δ⌋⌋⌊α⌋φ))))
  -- The (L-) rule:
  | freeL : PdlRule (L, R, some (Sum.inl (~'(⌊⌊δ⌋⌋⌊α⌋(φ : Formula)))))
                    (L.insert (~⌈⌈δ⌉⌉⌈α⌉φ), R, none)
  | freeR : PdlRule (L, R, some (Sum.inr (~'(⌊⌊δ⌋⌋⌊α⌋(φ : Formula)))))
                    (L, R.insert (~⌈⌈δ⌉⌉⌈α⌉φ), none)
  -- The (M) rule:
  | modL   {A X ξ} : X = ⟨L, R, some (Sum.inl (~'⌊·A⌋(ξ : AnyFormula)))⟩ → isBasic X → PdlRule X
                         ( match ξ with
                         | .normal φ => ⟨(~φ) :: projection A L, projection A R, none⟩
                         | .loaded χ => ⟨projection A L, projection A R, some (Sum.inl (~'χ))⟩ )
  | modR   {A X ξ} : X = ⟨L, R, some (Sum.inr (~'⌊·A⌋(ξ : AnyFormula)))⟩ → isBasic X → PdlRule X
                         ( match ξ with
                         | .normal φ => ⟨projection A L, (~φ) :: projection A R, none⟩
                         | .loaded χ => ⟨projection A L, projection A R, some (Sum.inr (~'χ))⟩ )

-- ClosedTableau [parent, grandparent, ...] child
--
-- A closed tableau for X is either of:
-- - a local tableau for X followed by closed tableaux for all end nodes,
-- - a PDL rule application
-- - a successful loaded repeat (MB condition six)

inductive ClosedTableau : History → TNode → Type
  | loc {X} (lt : LocalTableau X) : (∀ Y ∈ endNodesOf lt, ClosedTableau (X :: Hist) Y) → ClosedTableau Hist X
  | pdl {Δ Γ} : PdlRule Γ Δ → ClosedTableau (Γ :: Hist) Δ → ClosedTableau Hist Γ
  | rep {X Hist} (lpr : LoadedPathRepeat Hist X) : ClosedTableau Hist X

inductive provable : Formula → Prop
  | byTableauL {φ : Formula} : ClosedTableau .nil ⟨[~φ], [], none⟩ → provable φ
  | byTableauR {φ : Formula} : ClosedTableau .nil ⟨[], [~φ], none⟩ → provable φ

/-- A TNode is inconsistent if there exists a closed tableau for it. -/
def inconsistent : TNode → Prop
  | LR => Nonempty (ClosedTableau .nil LR)

/-- A TNode is consistent iff it is not inconsistent. -/
def consistent : TNode → Prop
  | LR => ¬inconsistent LR
