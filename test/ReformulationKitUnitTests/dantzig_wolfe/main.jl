# Integration tests for main dantzig_wolfe_decomposition function

using JuMP, ReformulationKit, Test

const RK = ReformulationKit


# Integration tests for dantzig_wolfe_decomposition()
function test_dantzig_wolfe_decomposition_standard_gap_ok()
    model, machines, jobs = create_standard_gap()
    
    reformulation = RK.dantzig_wolfe_decomposition(model, gap_annotation)
    
    @test reformulation isa RK.DantzigWolfeReformulation
    
    # Check master problem
    master = RK.master(reformulation)
    @test JuMP.num_variables(master) == 0  # No master variables in standard GAP
    @test JuMP.objective_sense(master) == MOI.MIN_SENSE
    
    # Check subproblems
    subproblems = RK.subproblems(reformulation)
    @test length(subproblems) == length(machines)
    
    for m in machines
        sp = subproblems[m]
        @test haskey(sp.obj_dict, :x)
        @test JuMP.num_variables(sp) == length(jobs)
        @test JuMP.objective_sense(sp) == MOI.MIN_SENSE
    end
end

function test_dantzig_wolfe_decomposition_gap_with_penalty_ok()
    model, machines, jobs = create_gap_with_penalty()
    
    reformulation = RK.dantzig_wolfe_decomposition(model, gap_annotation)
    
    @test reformulation isa RK.DantzigWolfeReformulation
    
    # Check master problem has penalty variables
    master = RK.master(reformulation)
    @test haskey(master.obj_dict, :penalty)
    @test JuMP.num_variables(master) == length(jobs)
    
    # Check master has assignment constraints
    @test haskey(master.obj_dict, :assignment)
    
    # Check subproblems still have x variables and capacity constraints
    subproblems = RK.subproblems(reformulation)
    for m in machines
        sp = subproblems[m]
        @test haskey(sp.obj_dict, :x)
        @test haskey(sp.obj_dict, :capacity_constr)
        @test JuMP.num_variables(sp) == length(jobs)
    end
end

function test_dantzig_wolfe_decomposition_return_type_ok()
    model = create_minimal_gap()
    
    reformulation = RK.dantzig_wolfe_decomposition(model, gap_annotation)
    
    @test reformulation isa RK.DantzigWolfeReformulation
    @test RK.master(reformulation) isa JuMP.Model
    @test RK.subproblems(reformulation) isa Dict{Any,JuMP.Model}
    @test reformulation.convexity_constraints_lb isa Dict{Any,Any}
    @test reformulation.convexity_constraints_ub isa Dict{Any,Any}
end

function test_dantzig_wolfe_decomposition_convexity_constraints_ok()
    model, machines, jobs = create_standard_gap()
    
    reformulation = RK.dantzig_wolfe_decomposition(model, gap_annotation)
    
    # Check convexity constraints exist for each subproblem
    @test length(reformulation.convexity_constraints_lb) == length(machines)
    @test length(reformulation.convexity_constraints_ub) == length(machines)
    
    for m in machines
        @test haskey(reformulation.convexity_constraints_lb, m)
        @test haskey(reformulation.convexity_constraints_ub, m)
        @test reformulation.convexity_constraints_lb[m] isa JuMP.ConstraintRef
        @test reformulation.convexity_constraints_ub[m] isa JuMP.ConstraintRef
    end
end

function test_dantzig_wolfe_decomposition_variable_properties_preserved_ok()
    model, machines, jobs = create_mixed_gap()
    
    reformulation = RK.dantzig_wolfe_decomposition(model, mixed_gap_annotation)
    
    # Check binary variables are preserved in subproblems
    subproblems = RK.subproblems(reformulation)
    for m in machines
        sp = subproblems[m]
        for j in jobs
            x_var = sp[:x][m, j]
            @test JuMP.is_binary(x_var)
        end
    end
    
    # Check continuous variables are preserved in subproblems
    for m in machines
        sp = subproblems[m]
        for j in jobs
            y_var = sp[:y][m, j]
            @test !JuMP.is_binary(y_var)
            @test !JuMP.is_integer(y_var)
            @test JuMP.lower_bound(y_var) == 0.0
        end
    end
    
    # Check integer variables are preserved in master
    master = RK.master(reformulation)
    for j in jobs
        z_var = master[:z][j]
        @test JuMP.is_integer(z_var)
        @test !JuMP.is_binary(z_var)
    end
end

function test_dantzig_wolfe_decomposition_objective_decomposition_ok()
    model, machines, jobs = create_standard_gap()
    
    reformulation = RK.dantzig_wolfe_decomposition(model, gap_annotation)
    
    # Master should have empty objective (no master variables)
    master = RK.master(reformulation)
    master_obj = JuMP.objective_function(master)
    @test master_obj isa JuMP.AffExpr
    @test isempty(master_obj.terms)
    
    # Each subproblem should have objective terms for its variables only
    subproblems = RK.subproblems(reformulation)
    for m in machines
        sp = subproblems[m]
        sp_obj = JuMP.objective_function(sp)
        @test sp_obj isa JuMP.AffExpr
        @test !isempty(sp_obj.terms)
        
        # All variables in objective should belong to this subproblem
        for var in keys(sp_obj.terms)
            @test JuMP.owner_model(var) == sp
        end
    end
end

function test_dantzig_wolfe_decomposition_subproblem_extensions_ok()
    model, machines, jobs = create_gap_with_penalty()
    
    reformulation = RK.dantzig_wolfe_decomposition(model, gap_annotation)
    
    subproblems = RK.subproblems(reformulation)
    for m in machines
        sp = subproblems[m]
        
        # Check coupling constraint mapping extension exists
        @test haskey(sp.ext, :dw_coupling_constr_mapping)
        @test sp.ext[:dw_coupling_constr_mapping] isa ReformulationKit.CouplingConstraintMapping
        
        # Check original cost mapping extension exists
        @test haskey(sp.ext, :dw_sp_var_original_cost)
        @test sp.ext[:dw_sp_var_original_cost] isa ReformulationKit.OriginalCostMapping
    end
end

function test_dantzig_wolfe_decomposition_minimal_problem_ok()
    model = create_minimal_gap()
    
    reformulation = RK.dantzig_wolfe_decomposition(model, gap_annotation)
    
    @test reformulation isa RK.DantzigWolfeReformulation
    @test length(RK.subproblems(reformulation)) == 1
    @test length(reformulation.convexity_constraints_lb) == 1
    @test length(reformulation.convexity_constraints_ub) == 1
    
    # Check single subproblem structure
    sp = RK.subproblems(reformulation)[1]
    @test JuMP.num_variables(sp) == 1
    @test haskey(sp.obj_dict, :x)
    @test haskey(sp.obj_dict, :capacity_constr)
end

function test_unit_main_decomposition()
    @testset "[main] basic functionality" begin
        test_dantzig_wolfe_decomposition_standard_gap_ok()
        test_dantzig_wolfe_decomposition_gap_with_penalty_ok()
        test_dantzig_wolfe_decomposition_return_type_ok()
    end

    @testset "[main] structure validation" begin
        test_dantzig_wolfe_decomposition_convexity_constraints_ok()
        test_dantzig_wolfe_decomposition_variable_properties_preserved_ok()
        test_dantzig_wolfe_decomposition_objective_decomposition_ok()
    end

    @testset "[main] extensions and mappings" begin
        test_dantzig_wolfe_decomposition_subproblem_extensions_ok()
    end

    @testset "[main] edge cases" begin
        test_dantzig_wolfe_decomposition_minimal_problem_ok()
    end
end