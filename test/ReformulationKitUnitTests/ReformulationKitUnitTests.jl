module ReformulationKitUnitTests

using JuMP, MathOptInterface, ReformulationKit, Test

const RK = ReformulationKit
const MOI = MathOptInterface

# Annotation functions for testing
dw_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine)
dw_annotation(::Val{:cov}, job) = RK.dantzig_wolfe_master()
dw_annotation(::Val{:knp}, machine) = RK.dantzig_wolfe_subproblem(machine)

# Helper functions for test data creation
function create_simple_problem()
    J = 1:3
    M = 1:2
    c = [1 2 3; 4 5 6]
    w = [1 1 1; 2 2 2]
    Q = [2, 4]

    model = Model()
    @variable(model, x[M, J], Bin)
    @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
    @constraint(model, knp[m in M], sum(w[m, j] * x[m, j] for j in J) <= Q[m])
    @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

    return model, J, M, c, w, Q
end

function create_minimal_problem()
    model = Model()
    @variable(model, x[1:1, 1:1], Bin)
    @constraint(model, cov[j in 1:1], sum(x[m, j] for m in 1:1) >= 1)
    @constraint(model, knp[m in 1:1], sum(x[m, j] for j in 1:1) <= 1)
    @objective(model, Min, sum(x[m, j] for m in 1:1, j in 1:1))
    return model
end

# Basic structure tests
function test_reformulation_ok()
    model, J, M, c, w, Q = create_simple_problem()
    reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    
    @test reformulation isa RK.Reformulation

    # master
    master = RK.master(reformulation)
    @test num_variables(master) == 0
    @test num_constraints(master, count_variable_in_set_constraints=false) == 5
    @test objective_sense(master) == MIN_SENSE

    # subproblems

    subproblems = RK.subproblems(reformulation)
    @test length(subproblems) == 2
    for (i, sp) in enumerate(subproblems)
        @test num_variables(sp) == 3
        @test objective_sense(sp) == MIN_SENSE
        @test num_constraints(sp, count_variable_in_set_constraints=false) == 1
    end

    @test length(reformulation.convexity_constraints) == 2
    @test length(reformulation.coupling_constraints) == 3
end

# Variable annotation tests
function test_variable_assignment_ok()
    J = 1:2
    M = 1:2
    model = Model()
    @variable(model, x[M, J], Bin)
    @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
    @constraint(model, knp[m in M], sum(x[m, j] for j in J) <= 2)
    @objective(model, Min, sum(x[m, j] for m in M, j in J))

    reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    subproblems = RK.subproblems(reformulation)

    println(model)
    println("----")
    println(RK.master(reformulation))
    println("----")
    println(subproblems[1])
    println("----")
    println(subproblems[2])

    @show subproblems[1].ext[:dw_mapping]

    subproblem_m1 = subproblems[1]
    x_m1 = subproblem_m1[:x]
    @show x_m1
    @show x_m1[1,1]
    @show x_m1[1,2]

end

# # Constraint annotation tests
# function test_coupling_constraints_in_master_ok()
#     J = 1:2
#     M = 1:2
#     w = [1 1; 2 2]
#     Q = [1, 2]
    
#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(w[m, j] * x[m, j] for j in J) <= Q[m])
#     @objective(model, Min, sum(x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    
#     coupling_keys = keys(reformulation.coupling_constraints)
#     cov_constraints = [k for k in coupling_keys if k[1] == :cov]
#     @test length(cov_constraints) == 2
# end

# function test_convexity_constraints_exist_ok()
#     J = 1:2
#     M = 1:2
#     w = [1 1; 2 2]
#     Q = [1, 2]
    
#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(w[m, j] * x[m, j] for j in J) <= Q[m])
#     @objective(model, Min, sum(x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    
#     convexity_keys = keys(reformulation.convexity_constraints)
#     @test 1 in convexity_keys
#     @test 2 in convexity_keys
# end

# function test_subproblem_constraints_exist_ok()
#     J = 1:2
#     M = 1:2
#     w = [1 1; 2 2]
#     Q = [1, 2]
    
#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(w[m, j] * x[m, j] for j in J) <= Q[m])
#     @objective(model, Min, sum(x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
#     subproblems = RK.subproblems(reformulation)
    
#     for (i, sp) in enumerate(subproblems)
#         constraints = all_constraints(sp, include_variable_in_set_constraints=false)
#         @test length(constraints) == 1
#     end
# end

# # Objective distribution tests
# function test_subproblem_linear_objective_ok()
#     J = 1:2
#     M = 1:2
#     c = [1 2; 3 4]
    
#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(x[m, j] for j in J) <= 2)
#     @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
#     subproblems = RK.subproblems(reformulation)
    
#     for (i, sp) in enumerate(subproblems)
#         obj = objective_function(sp)
#         @test obj isa AffExpr
#     end
# end

# # Column generation functionality tests
# function test_lambda_variable_addition_ok()
#     J = 1:3
#     M = 1:2
#     c = [1 2 3; 4 5 6]
    
#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(x[m, j] for j in J) <= 2)
#     @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
#     master = RK.master(reformulation)
    
#     initial_vars = num_variables(master)
#     λ = @variable(master, lower_bound=0, base_name="test_λ")
    
#     @test num_variables(master) == initial_vars + 1
# end

# function test_convexity_constraint_update_ok()
#     J = 1:3
#     M = 1:2
#     c = [1 2 3; 4 5 6]
    
#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(x[m, j] for j in J) <= 2)
#     @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
#     master = RK.master(reformulation)
    
#     λ = @variable(master, lower_bound=0, base_name="test_λ")
#     conv_constraint = reformulation.convexity_constraints[1]
    
#     @test_nowarn set_normalized_coefficient(conv_constraint, λ, 1.0)
# end

# function test_coupling_constraint_update_ok()
#     J = 1:3
#     M = 1:2
#     c = [1 2 3; 4 5 6]
    
#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(x[m, j] for j in J) <= 2)
#     @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
#     master = RK.master(reformulation)
    
#     λ = @variable(master, lower_bound=0, base_name="test_λ")
#     coupling_constraint = first(values(reformulation.coupling_constraints))
    
#     @test_nowarn set_normalized_coefficient(coupling_constraint, λ, 1.0)
# end

# function test_master_objective_setting_ok()
#     J = 1:3
#     M = 1:2
#     c = [1 2 3; 4 5 6]
    
#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(x[m, j] for j in J) <= 2)
#     @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
#     master = RK.master(reformulation)
    
#     λ = @variable(master, lower_bound=0, base_name="test_λ")
#     @objective(master, Min, 5.0 * λ)
    
#     @test objective_sense(master) == MIN_SENSE
#     obj_func = objective_function(master)
#     @test coefficient(obj_func, λ) == 5.0
# end

# # Edge case tests
# function test_minimal_problem_ok()
#     model = create_minimal_problem()
#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    
#     @test length(RK.subproblems(reformulation)) >= 1
#     @test length(reformulation.convexity_constraints) >= 1
#     @test length(reformulation.coupling_constraints) >= 1
# end

# function test_different_dimensions_ok()
#     model = Model()
#     @variable(model, x[1:2, 1:2], Bin)
#     @show typeof(x)
#     @show x[1, 1]
#     @constraint(model, cov[j in 1:2], sum(x[m, j] for m in 1:2) >= 1)
#     @constraint(model, knp[m in 1:2], sum(x[m, j] for j in 1:2) <= 2)
#     @objective(model, Min, sum(x[m, j] for m in 1:2, j in 1:2))
    
#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    
#     @test length(RK.subproblems(reformulation)) > 0
#     @test length(reformulation.coupling_constraints) == 2
# end

# # Column generation demonstration
# function demonstrate_column_generation()
#     println("\\n=== Column Generation Demonstration ===")
    
#     J = 1:7
#     M = 1:2
#     c = [1 3 2 2 1 1 1; 2 3 1 1 2 2 1]
#     w = [2 3 3 4 2 3 2; 2 3 3 2 1 1 1]
#     Q = [10, 12]

#     model = Model()
#     @variable(model, x[M, J], Bin)
#     @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
#     @constraint(model, knp[m in M], sum(w[m, j] * x[m, j] for j in J) <= Q[m])
#     @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

#     reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
#     master = RK.master(reformulation)
    
#     # Generate example columns
#     columns = [
#         (subproblem_id=1, values=[1, 1, 0, 0, 0, 0, 0], obj_coeff=4, coupling_coeffs=[1, 1, 0, 0, 0, 0, 0]),
#         (subproblem_id=1, values=[0, 0, 1, 1, 1, 0, 0], obj_coeff=5, coupling_coeffs=[0, 0, 1, 1, 1, 0, 0]),
#         (subproblem_id=2, values=[0, 0, 0, 0, 0, 1, 1], obj_coeff=3, coupling_coeffs=[0, 0, 0, 0, 0, 1, 1])
#     ]
    
#     # Add λ variables
#     λ_vars = []
#     for (col_idx, column) in enumerate(columns)
#         λ = @variable(master, lower_bound=0, base_name="λ_$(column.subproblem_id)_$(col_idx)")
#         push!(λ_vars, λ)
#     end
    
#     # Set master objective
#     master_obj = AffExpr(0.0)
#     for (col_idx, column) in enumerate(columns)
#         add_to_expression!(master_obj, column.obj_coeff, λ_vars[col_idx])
#     end
#     @objective(master, Min, master_obj)
    
#     # Update convexity constraints
#     for (col_idx, column) in enumerate(columns)
#         conv_constraint = reformulation.convexity_constraints[column.subproblem_id]
#         set_normalized_coefficient(conv_constraint, λ_vars[col_idx], 1.0)
#     end
    
#     # Update coupling constraints
#     for (constraint_key, coupling_constraint) in reformulation.coupling_constraints
#         if constraint_key[1] == :cov
#             job = constraint_key[2][1]
#             for (col_idx, column) in enumerate(columns)
#                 coeff = column.coupling_coeffs[job]
#                 if coeff > 0
#                     set_normalized_coefficient(coupling_constraint, λ_vars[col_idx], coeff)
#                 end
#             end
#         end
#     end
    
#     println("Final master problem with columns:")
#     println(master)
# end

# Main test runner functions
function test_unit_dantzig_wolfe_decomposition()
    @testset "[dantzig_wolfe]" begin
        #test_reformulation_ok()
        test_variable_assignment_ok()
    end

    # @testset "[dantzig_wolfe] constraint annotations" begin
    #     test_coupling_constraints_in_master_ok()
    #     test_convexity_constraints_exist_ok()
    #     test_subproblem_constraints_exist_ok()
    # end

    # @testset "[dantzig_wolfe] objective distribution" begin
    #     test_subproblem_linear_objective_ok()
    # end

    # @testset "[dantzig_wolfe] column generation" begin
    #     test_lambda_variable_addition_ok()
    #     test_convexity_constraint_update_ok()
    #     test_coupling_constraint_update_ok()
    #     test_master_objective_setting_ok()
    # end

    # @testset "[dantzig_wolfe] edge cases" begin
    #     test_minimal_problem_ok()
    #     test_different_dimensions_ok()
    # end
end

function run()
    @testset "ReformulationKit Unit Tests" begin
        test_unit_dantzig_wolfe_decomposition()
    end
    
    # Demonstrate column generation
    #demonstrate_column_generation()
end

end