# Copyright (c) 2025 Nablarise. All rights reserved.
# Author: Guillaume Marques <guillaume@nablarise.com>
# SPDX-License-Identifier: Proprietary

"""
    compute_column_cost(
        callbacks,
        solution::PrimalMoiSolution
    ) -> Float64

Compute the objective coefficient for a new column based on a subproblem solution.

# Arguments
- `callbacks`: Callback implementation
- `solution`: Primal solution from the pricing subproblem containing variable values

# Returns
- `Float64`: The objective coefficient for the new column in the master problem
"""
function compute_column_cost end

"""
    compute_column_coefficients(
        callbacks,
        solution::PrimalMoiSolution,
    ) -> Dict{MOI.ConstraintIndex, Float64}

Compute the constraint coefficients for a new column (coupling constraints only).

For each coupling constraint in the master problem, this computes how much the
column contributes to that constraint. For a subproblem solution x and constraint i
with coefficient vector a_i, this computes a_i'x.

**Important**: Do NOT include convexity constraint coefficients in the returned dictionary.
MatheuristicKit handles convexity constraints automatically (they always have coefficient 1.0).

# Arguments
- `callbacks`: Callback implementation
- `solution`: Primal solution from the pricing subproblem containing variable values

# Returns
- `Dict{MOI.ConstraintIndex, Float64}`: Mapping from constraint indices to coefficient values.
  Only include constraints with non-zero coefficients (sparse representation).
"""
function compute_column_coefficients end

"""
    compute_reduced_costs(
        callbacks,
        master_dual_solution::DualMoiSolution
    ) -> Dict{MOI.VariableIndex, Float64}

Compute the reduced costs for all variables in a subproblem.

The reduced cost for variable j in the subproblem is: c_j - Σ(a_ij * π_i) where:
- c_j is the original cost
- a_ij are the coupling constraint coefficients
- π_i are the dual values from the master problem

This is used to update the subproblem objective before pricing optimization.

# Arguments
- `callbacks`: Callback implementation
- `master_dual_solution`: Dual solution from the master problem containing dual values

# Returns
- `Dict{MOI.VariableIndex, Float64}`: Mapping from subproblem variable indices to reduced costs
"""
function compute_reduced_costs end
