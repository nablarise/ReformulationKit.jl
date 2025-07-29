# Unit tests for reformulation structure in dantzig_wolfe/reformulation.jl

using JuMP, ReformulationKit, Test

const RK = ReformulationKit


# Tests for DantzigWolfeReformulation struct
function test_master_accessor_ok()
    master_model = Model()
    @variable(master_model, test_var)
    subproblems = Dict(1 => Model())
    convexity_lb = Dict(1 => nothing)
    convexity_ub = Dict(1 => nothing)
    
    reformulation = RK.DantzigWolfeReformulation(master_model, subproblems, convexity_lb, convexity_ub)
    
    result = RK.master(reformulation)
    
    @test result === master_model
    @test haskey(result.obj_dict, :test_var)
end

function test_subproblems_accessor_ok()
    master_model = Model()
    subproblem1 = Model()
    subproblem2 = Model()
    @variable(subproblem1, x1)
    @variable(subproblem2, x2)
    
    subproblems = Dict(1 => subproblem1, 2 => subproblem2)
    convexity_lb = Dict(1 => nothing, 2 => nothing)
    convexity_ub = Dict(1 => nothing, 2 => nothing)
    
    reformulation = RK.DantzigWolfeReformulation(master_model, subproblems, convexity_lb, convexity_ub)
    
    result = RK.subproblems(reformulation)
    
    @test length(result) == 2
    @test haskey(result[1].obj_dict, :x1)
    @test haskey(result[2].obj_dict, :x2)
end

function test_reformulation_with_gap_structure_ok()
    # Test using actual GAP structure
    original_model, machines, jobs = create_mixed_gap()
    
    # Create a mock reformulation structure
    master_model = Model()
    @variable(master_model, z[jobs], Int)
    
    subproblems = Dict()
    for m in machines
        sp_model = Model()
        @variable(sp_model, x[m:m, jobs], Bin)
        @variable(sp_model, y[m:m, jobs] >= 0)
        subproblems[m] = sp_model
    end
    
    convexity_lb = Dict(m => nothing for m in machines)
    convexity_ub = Dict(m => nothing for m in machines)
    
    reformulation = RK.DantzigWolfeReformulation(master_model, subproblems, convexity_lb, convexity_ub)
    
    # Test structure
    @test length(RK.subproblems(reformulation)) == length(machines)
    @test haskey(RK.master(reformulation).obj_dict, :z)
    
    for m in machines
        sp = RK.subproblems(reformulation)[m]
        @test haskey(sp.obj_dict, :x)
        @test haskey(sp.obj_dict, :y)
    end
end

function test_reformulation_empty_structures_ok()
    # Test with empty subproblems and constraints
    master_model = Model()
    subproblems = Dict{Any,Model}()
    convexity_lb = Dict{Any,Any}()
    convexity_ub = Dict{Any,Any}()
    
    reformulation = RK.DantzigWolfeReformulation(master_model, subproblems, convexity_lb, convexity_ub)
    
    @test reformulation isa RK.DantzigWolfeReformulation
    @test isempty(RK.subproblems(reformulation))
    @test isempty(reformulation.convexity_constraints_lb)
    @test isempty(reformulation.convexity_constraints_ub)
end

function test_unit_reformulation_structure()
    @testset "[reformulation] constructor" begin
        test_reformulation_with_gap_structure_ok()
        test_reformulation_empty_structures_ok()
    end

    @testset "[reformulation] accessors" begin
        test_master_accessor_ok()
        test_subproblems_accessor_ok()
    end
end