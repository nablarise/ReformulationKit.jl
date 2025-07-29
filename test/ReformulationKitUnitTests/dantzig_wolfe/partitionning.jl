# Unit tests for partitioning methods in dantzig_wolfe/partitionning.jl

using JuMP, ReformulationKit, Test

const RK = ReformulationKit


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

function test_unit_partitioning()
    @testset "[partitioning] master variables" begin
        test_master_variables_empty_ok()
        test_master_variables_penalty_vars_ok()
        test_master_variables_mixed_dimensions_ok()
    end

    @testset "[partitioning] subproblem variables" begin
        test_partition_subproblem_variables_assignment_vars_ok()
        test_partition_subproblem_variables_multiple_machines_ok()
        test_partition_subproblem_variables_single_machine_ok()
    end

    @testset "[partitioning] master constraints" begin
        test_master_constraints_assignment_constraints_ok()
        test_master_constraints_empty_ok()
    end

    @testset "[partitioning] subproblem constraints" begin
        test_partition_subproblem_constraints_capacity_ok()
        test_partition_subproblem_constraints_multiple_machines_ok()
    end
end