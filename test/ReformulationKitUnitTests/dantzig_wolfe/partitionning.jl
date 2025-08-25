# Unit tests for partitioning methods in dantzig_wolfe/partitionning.jl

using JuMP, ReformulationKit, Test

const RK = ReformulationKit

# Helper function to create model with scalar master variable and constraint
function create_gap_with_scalar_master()
    machines = 1:2
    jobs = 1:3
    
    model = Model()
    @variable(model, x[machines, jobs], Bin)
    @variable(model, scalar_master_var >= 0)  # Scalar master variable
    @constraint(model, assignment[j in jobs], sum(x[m, j] for m in machines) >= 1)
    @constraint(model, capacity_constr[m in machines], sum(x[m, j] for j in jobs) <= 2)
    @constraint(model, scalar_master_constraint, scalar_master_var <= 10)  # Scalar master constraint
    @objective(model, Min, sum(x[m, j] for m in machines, j in jobs) + scalar_master_var)
    
    return model, machines, jobs
end

# Helper function to create model with scalar subproblem variable and constraint  
function create_gap_with_scalar_subproblem()
    machines = 1:2
    jobs = 1:3
    
    model = Model()
    @variable(model, x[machines, jobs], Bin)
    @variable(model, scalar_sp_var >= 0)  # Scalar subproblem variable
    @constraint(model, assignment[j in jobs], sum(x[m, j] for m in machines) >= 1)
    @constraint(model, capacity_constr[m in machines], sum(x[m, j] for j in jobs) <= 2)
    @constraint(model, scalar_sp_constraint, scalar_sp_var <= 5)  # Scalar subproblem constraint
    @objective(model, Min, sum(x[m, j] for m in machines, j in jobs) + scalar_sp_var)
    
    return model, machines, jobs
end

# Annotation functions for scalar variable/constraint tests
scalar_master_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine)
scalar_master_annotation(::Val{:scalar_master_var}) = RK.dantzig_wolfe_master()  # Scalar master variable
scalar_master_annotation(::Val{:assignment}, job) = RK.dantzig_wolfe_master()
scalar_master_annotation(::Val{:capacity_constr}, machine) = RK.dantzig_wolfe_subproblem(machine)
scalar_master_annotation(::Val{:scalar_master_constraint}) = RK.dantzig_wolfe_master()  # Scalar master constraint

scalar_subproblem_annotation(::Val{:x}, machine, job) = RK.dantzig_wolfe_subproblem(machine)
scalar_subproblem_annotation(::Val{:scalar_sp_var}) = RK.dantzig_wolfe_subproblem(1)  # Scalar subproblem variable
scalar_subproblem_annotation(::Val{:assignment}, job) = RK.dantzig_wolfe_master()
scalar_subproblem_annotation(::Val{:capacity_constr}, machine) = RK.dantzig_wolfe_subproblem(machine)  
scalar_subproblem_annotation(::Val{:scalar_sp_constraint}) = RK.dantzig_wolfe_subproblem(1)  # Scalar subproblem constraint


# Tests for _master_variables()
function test_master_variables_empty_ok()
    model, machines, jobs = create_standard_gap()
    
    result = RK._master_variables(model, gap_annotation)
    
    @test result isa Dict{Symbol,Set{Tuple}}
    @test isempty(result)
end

function test_master_variables_penalty_vars_ok()
    model, machines, jobs = create_gap_with_penalty()
    
    result = RK._master_variables(model, gap_annotation)
    
    @test result isa Dict{Symbol,Set{Tuple}}
    @test haskey(result, :penalty)
    @test result[:penalty] == Set([(j,) for j in jobs])
end

function test_master_variables_mixed_dimensions_ok()
    model, machines, jobs = create_mixed_gap()
    
    result = RK._master_variables(model, mixed_gap_annotation)
    
    @test result isa Dict{Symbol,Set{Tuple}}
    @test haskey(result, :z)
    @test result[:z] == Set([(j,) for j in jobs])
end

# Tests for _partition_subproblem_variables()
function test_partition_subproblem_variables_assignment_vars_ok()
    model, machines, jobs = create_standard_gap()
    
    result = RK._partition_subproblem_variables(model, gap_annotation)
    
    @test result isa Dict{Any,Dict{Symbol,Set{Tuple}}}
    @test length(result) == length(machines)
    for m in machines
        @test haskey(result, m)
        @test haskey(result[m], :x)
        @test result[m][:x] == Set([(m, j) for j in jobs])
    end
end

function test_partition_subproblem_variables_multiple_machines_ok()
    model, machines, jobs = create_standard_gap()
    
    result = RK._partition_subproblem_variables(model, gap_annotation)
    
    @test length(result) == 2
    @test haskey(result, 1)
    @test haskey(result, 2)
    @test result[1][:x] == Set([(1, j) for j in jobs])
    @test result[2][:x] == Set([(2, j) for j in jobs])
end

function test_partition_subproblem_variables_single_machine_ok()
    model = create_minimal_gap()
    
    result = RK._partition_subproblem_variables(model, gap_annotation)
    
    @test length(result) == 1
    @test haskey(result, 1)
    @test result[1][:x] == Set([(1, 1)])
end

# Tests for _master_constraints()
function test_master_constraints_assignment_constraints_ok()
    model, machines, jobs = create_standard_gap()
    
    result = RK._master_constraints(model, gap_annotation)
    
    @test result isa Dict{Symbol,Set{Tuple}}
    @test haskey(result, :assignment)
    @test result[:assignment] == Set([(j,) for j in jobs])
end

function test_master_constraints_empty_ok()
    # Create a model with no master constraints
    model = Model()
    @variable(model, x[1:2, 1:2], Bin)
    @constraint(model, capacity_constr[m in 1:2], sum(x[m, j] for j in 1:2) <= 1)
    
    result = RK._master_constraints(model, gap_annotation)
    
    @test result isa Dict{Symbol,Set{Tuple}}
    @test isempty(result)
end

# Tests for _partition_subproblem_constraints()
function test_partition_subproblem_constraints_capacity_ok()
    model, machines, jobs = create_standard_gap()
    
    result = RK._partition_subproblem_constraints(model, gap_annotation)
    
    @test result isa Dict{Any,Dict{Symbol,Set{Tuple}}}
    @test length(result) == length(machines)
    for m in machines
        @test haskey(result, m)
        @test haskey(result[m], :capacity_constr)
        @test result[m][:capacity_constr] == Set([(m,)])
    end
end

function test_partition_subproblem_constraints_multiple_machines_ok()
    model, machines, jobs = create_standard_gap()
    
    result = RK._partition_subproblem_constraints(model, gap_annotation)
    
    @test length(result) == 2
    @test haskey(result, 1)
    @test haskey(result, 2)
    @test result[1][:capacity_constr] == Set([(1,)])
    @test result[2][:capacity_constr] == Set([(2,)])
end

# Tests for scalar variables
function test_master_variables_scalar_ok()
    model, machines, jobs = create_gap_with_scalar_master()
    
    result = RK._master_variables(model, scalar_master_annotation)
    
    @test result isa Dict{Symbol,Set{Tuple}}
    @test haskey(result, :scalar_master_var)
    @test result[:scalar_master_var] == Set{Tuple}([()]) # Should contain empty tuple, not be empty
    @test length(result[:scalar_master_var]) == 1
    @test () in result[:scalar_master_var]
end

function test_partition_subproblem_variables_scalar_ok()
    model, machines, jobs = create_gap_with_scalar_subproblem()
    
    result = RK._partition_subproblem_variables(model, scalar_subproblem_annotation)
    
    @test result isa Dict{Any,Dict{Symbol,Set{Tuple}}}
    @test haskey(result, 1)
    @test haskey(result[1], :scalar_sp_var)
    @test result[1][:scalar_sp_var] == Set{Tuple}([()]) # Should contain empty tuple, not be empty
    @test length(result[1][:scalar_sp_var]) == 1
    @test () in result[1][:scalar_sp_var]
end

# Tests for scalar constraints  
function test_master_constraints_scalar_ok()
    model, machines, jobs = create_gap_with_scalar_master()
    
    result = RK._master_constraints(model, scalar_master_annotation)
    
    @test result isa Dict{Symbol,Set{Tuple}}
    @test haskey(result, :scalar_master_constraint)
    @test result[:scalar_master_constraint] == Set{Tuple}([()]) # Should contain empty tuple, not be empty
    @test length(result[:scalar_master_constraint]) == 1
    @test () in result[:scalar_master_constraint]
end

function test_partition_subproblem_constraints_scalar_ok()
    model, machines, jobs = create_gap_with_scalar_subproblem()
    
    result = RK._partition_subproblem_constraints(model, scalar_subproblem_annotation)
    
    @test result isa Dict{Any,Dict{Symbol,Set{Tuple}}}
    @test haskey(result, 1)
    @test haskey(result[1], :scalar_sp_constraint)
    @test result[1][:scalar_sp_constraint] == Set{Tuple}([()]) # Should contain empty tuple, not be empty
    @test length(result[1][:scalar_sp_constraint]) == 1
    @test () in result[1][:scalar_sp_constraint]
end

function test_unit_partitioning()
    @testset "[partitioning] master variables" begin
        test_master_variables_empty_ok()
        test_master_variables_penalty_vars_ok()
        test_master_variables_mixed_dimensions_ok()
        test_master_variables_scalar_ok()
    end

    @testset "[partitioning] subproblem variables" begin
        test_partition_subproblem_variables_assignment_vars_ok()
        test_partition_subproblem_variables_multiple_machines_ok()
        test_partition_subproblem_variables_single_machine_ok()
        test_partition_subproblem_variables_scalar_ok()
    end

    @testset "[partitioning] master constraints" begin
        test_master_constraints_assignment_constraints_ok()
        test_master_constraints_empty_ok()
        test_master_constraints_scalar_ok()
    end

    @testset "[partitioning] subproblem constraints" begin
        test_partition_subproblem_constraints_capacity_ok()
        test_partition_subproblem_constraints_multiple_machines_ok()
        test_partition_subproblem_constraints_scalar_ok()
    end
end