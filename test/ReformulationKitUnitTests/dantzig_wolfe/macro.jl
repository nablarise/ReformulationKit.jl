# Copyright (c) 2025 Nablarise. All rights reserved.
# Author: Guillaume Marques <guillaume@nablarise.com>
# SPDX-License-Identifier: Proprietary

function test_macro_basic_gap_ok()
    J = 1:2
    M = 1:2
    c = [1 2; 3 4]
    
    model = Model()
    @variable(model, x[M, J], Bin)
    @constraint(model, assignment[j in J], sum(x[m, j] for m in M) >= 1)
    @constraint(model, capacity[m in M], sum(x[m, j] for j in J) <= 2)
    @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))
    
    reformulation = @dantzig_wolfe model begin
        x[m, _] => subproblem(m)
        assignment[_] => master()
        capacity[m] => subproblem(m)
    end
    
    @test reformulation isa RK.DantzigWolfeReformulation
    @test length(RK.subproblems(reformulation)) == 2
    
    master = RK.master(reformulation)
    @test JuMP.num_variables(master) == 0  # No master variables in this GAP
    
    subproblems = RK.subproblems(reformulation)
    for (m, sp) in subproblems
        @test JuMP.num_variables(sp) == 2  # x variables for 2 jobs
        @test haskey(sp.obj_dict, :x)
        @test haskey(sp.obj_dict, :capacity)
    end
end

function test_macro_gap_with_penalties_ok()
    machines = 1:2
    jobs = 1:3
    assignment_costs = [1 2 3; 4 5 6]
    penalty_costs = [10, 12, 8]
    capacities = [2, 2]
    
    model = Model()
    @variable(model, x[machines, jobs], Bin)
    @variable(model, penalty[jobs] >= 0)
    @constraint(model, assignment[j in jobs], 
                sum(x[m, j] for m in machines) + penalty[j] >= 1)
    @constraint(model, capacity_constr[m in machines], 
                sum(x[m, j] for j in jobs) <= capacities[m])
    @objective(model, Min, 
               sum(assignment_costs[m, j] * x[m, j] for m in machines, j in jobs) + 
               sum(penalty_costs[j] * penalty[j] for j in jobs))
    
    reformulation = @dantzig_wolfe model begin
        x[m, _] => subproblem(m)
        penalty[_] => master()
        assignment[_] => master()
        capacity_constr[m] => subproblem(m)
    end
    
    @test reformulation isa RK.DantzigWolfeReformulation
    @test length(RK.subproblems(reformulation)) == 2
    
    master = RK.master(reformulation)
    @test JuMP.num_variables(master) == 3  # penalty variables
    @test haskey(master.obj_dict, :penalty)
    @test haskey(master.obj_dict, :assignment)
    
    subproblems = RK.subproblems(reformulation)
    for (m, sp) in subproblems
        @test JuMP.num_variables(sp) == 3  # x variables for 3 jobs
        @test haskey(sp.obj_dict, :x)
        @test haskey(sp.obj_dict, :capacity_constr)
    end
end

function test_macro_single_index_patterns_ok()
    model = Model()
    @variable(model, y[1:3])
    @constraint(model, single_constr[i in 1:3], y[i] <= 1)
    @constraint(model, master_constr, sum(y) >= 1)
    @objective(model, Min, sum(y))
    
    reformulation = @dantzig_wolfe model begin
        y[i] => subproblem(i)
        single_constr[i] => subproblem(i)
        master_constr => master()
    end
    
    @test reformulation isa RK.DantzigWolfeReformulation
    @test length(RK.subproblems(reformulation)) == 3
    
    for i in 1:3
        sp = RK.subproblems(reformulation)[i]
        @test JuMP.num_variables(sp) == 1
        @test haskey(sp.obj_dict, :y)
        @test haskey(sp.obj_dict, :single_constr)
    end
end

function test_macro_no_index_patterns_ok()
    model = Model()
    @variable(model, x)
    @variable(model, y)
    @constraint(model, link, x + y <= 1)
    @objective(model, Min, x + y)
    
    reformulation = @dantzig_wolfe model begin
        x => subproblem(1)
        y => master()
        link => master()
    end
    
    @test reformulation isa RK.DantzigWolfeReformulation
    @test length(RK.subproblems(reformulation)) == 1
    
    master = RK.master(reformulation)
    @test haskey(master.obj_dict, :y)
    @test haskey(master.obj_dict, :link)
    
    sp = RK.subproblems(reformulation)[1]
    @test haskey(sp.obj_dict, :x)
end

function test_macro_error_malformed_pattern_nok()
    model = Model()
    @variable(model, x)
    
    @test_throws Exception @eval @dantzig_wolfe $model begin
        invalid_pattern => subproblem(1)
    end
end

function test_macro_error_malformed_assignment_nok()
    model = Model()
    @variable(model, x)
    
    @test_throws Exception @eval @dantzig_wolfe $model begin
        x => invalid_assignment(1)
    end
end

function test_macro_error_subproblem_no_args_nok()
    model = Model()
    @variable(model, x)
    
    @test_throws Exception @eval @dantzig_wolfe $model begin
        x => subproblem()
    end
end

function test_macro_error_master_with_args_nok()
    model = Model()
    @variable(model, x)
    
    @test_throws Exception @eval @dantzig_wolfe $model begin
        x => master(1)
    end
end

function test_macro_error_empty_block_nok()
    model = Model()
    @variable(model, x)
    
    @test_throws Exception @eval @dantzig_wolfe $model begin
    end
end

function test_macro_compatibility_with_callback_functions_ok()
    J = 1:2
    M = 1:2
    c = [1 2; 3 4]
    
    model = Model()
    @variable(model, x[M, J], Bin)
    @constraint(model, assignment[j in J], sum(x[m, j] for m in M) >= 1)
    @constraint(model, capacity[m in M], sum(x[m, j] for j in J) <= 2)
    @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))
    
    # Test macro version
    macro_reformulation = @dantzig_wolfe model begin
        x[m, _] => subproblem(m)
        assignment[_] => master()
        capacity[m] => subproblem(m)
    end
    
    # Test callback version  
    callback_annotation(::Val{:x}, m, j) = RK.dantzig_wolfe_subproblem(m)
    callback_annotation(::Val{:assignment}, j) = RK.dantzig_wolfe_master()
    callback_annotation(::Val{:capacity}, m) = RK.dantzig_wolfe_subproblem(m)
    
    callback_reformulation = RK.dantzig_wolfe_decomposition(model, callback_annotation)
    
    # Both should produce structurally similar results
    @test typeof(macro_reformulation) == typeof(callback_reformulation)
    @test length(RK.subproblems(macro_reformulation)) == length(RK.subproblems(callback_reformulation))
    
    macro_master = RK.master(macro_reformulation)
    callback_master = RK.master(callback_reformulation)
    @test JuMP.num_variables(macro_master) == JuMP.num_variables(callback_master)
    
    macro_sps = RK.subproblems(macro_reformulation)
    callback_sps = RK.subproblems(callback_reformulation)
    for m in M
        @test JuMP.num_variables(macro_sps[m]) == JuMP.num_variables(callback_sps[m])
    end
end

function test_macro_multiple_calls_no_conflicts_ok()
    # Test that multiple macro calls don't interfere with each other
    
    # First call
    model1 = Model()
    @variable(model1, x[1:2])
    @constraint(model1, c1, sum(x) <= 1)
    @objective(model1, Min, sum(x))
    
    reformulation1 = @dantzig_wolfe model1 begin
        x[i] => subproblem(i)
        c1 => master()
    end
    
    # Second call with different patterns
    model2 = Model()
    @variable(model2, y[1:3, 1:2])
    @constraint(model2, assignment[j in 1:2], sum(y[i, j] for i in 1:3) >= 1)
    @constraint(model2, capacity[i in 1:3], sum(y[i, j] for j in 1:2) <= 1)
    @objective(model2, Min, sum(y))
    
    reformulation2 = @dantzig_wolfe model2 begin
        y[i, _] => subproblem(i)
        assignment[_] => master()
        capacity[i] => subproblem(i)
    end
    
    # Both reformulations should be valid and independent
    @test reformulation1 isa RK.DantzigWolfeReformulation
    @test reformulation2 isa RK.DantzigWolfeReformulation
    @test length(RK.subproblems(reformulation1)) == 2
    @test length(RK.subproblems(reformulation2)) == 3
end

function test_unit_macro()
    @testset "[macro] basic functionality" begin
        test_macro_basic_gap_ok()
        test_macro_gap_with_penalties_ok()
        #test_macro_single_index_patterns_ok()
        #test_macro_no_index_patterns_ok()
    end
    
    @testset "[macro] error handling" begin
        test_macro_error_malformed_pattern_nok()
        test_macro_error_malformed_assignment_nok()
        test_macro_error_subproblem_no_args_nok()
        test_macro_error_master_with_args_nok()
        test_macro_error_empty_block_nok()
    end
    
    @testset "[macro] compatibility and isolation" begin
        test_macro_compatibility_with_callback_functions_ok()
        #test_macro_multiple_calls_no_conflicts_ok()
    end
end