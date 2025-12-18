# End-to-end tests for GAP scenarios with Dantzig-Wolfe decomposition

using JuMP, ReformulationKit, Test

const RK = ReformulationKit

# Basic GAP decomposition E2E test (moved from unit tests)
function test_e2e_basic_gap_decomposition_ok()
    # === INLINE MODEL DECLARATION ===
    J = 1:2
    M = 1:2
    c = [1 2; 3 4]
    
    model = Model()
    @variable(model, x[M, J], Bin)
    @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
    @constraint(model, knp[m in M], sum(x[m, j] for j in J) <= 2)
    @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J))

    # === FULL E2E WORKFLOW TEST ===
    reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    subproblems = RK.subproblems(reformulation)

    # Test reformulation structure
    @test reformulation isa RK.DantzigWolfeReformulation
    @test length(subproblems) == 2

    # Test master problem
    master = RK.master(reformulation)
    @test JuMP.num_variables(master) == 0  # No master variables in basic GAP
    @test JuMP.objective_sense(master) == MOI.MIN_SENSE

    # Test subproblems structure
    for (m, sp) in subproblems
        @test JuMP.num_variables(sp) == 2  # x variables for 2 jobs
        @test JuMP.objective_sense(sp) == MOI.MIN_SENSE
        @test JuMP.num_constraints(sp, count_variable_in_set_constraints=false) == 1  # capacity constraint
    end

    # Test convexity and coupling constraints
    @test length(reformulation.convexity_constraints_lb) == 2
    @test length(reformulation.convexity_constraints_ub) == 2

    # === MAPPING STRUCTURES CONTENT VALIDATION ===
    # Test all subproblems have proper mapping extensions
    for (m, sp) in subproblems
        @test haskey(sp.ext, :dw_colgen_callbacks)
        @test isa(RK.coupling_mapping(sp), ReformulationKit.CouplingConstraintMapping)
        @test isa(RK.cost_mapping(sp), ReformulationKit.OriginalCostMapping)
        
        # Test original cost mapping using helper methods
        cost_mapping = RK.cost_mapping(sp)
        @test ReformulationKit.get_cost(cost_mapping, JuMP.index(sp[:x][m, 1])) == c[m,1]
        @test ReformulationKit.get_cost(cost_mapping, JuMP.index(sp[:x][m, 2])) == c[m,2]
        
        # Test coupling constraint mapping structure
        coupling_mapping = RK.coupling_mapping(sp)
        @test isa(coupling_mapping, ReformulationKit.CouplingConstraintMapping)
        @test length(coupling_mapping) == 2  # Two variables with constraint coefficients
        
        # Test that we can retrieve coefficients using the new API
        var1_coeffs = ReformulationKit.get_variable_coefficients(coupling_mapping, JuMP.index(sp[:x][m, 1]))
        var2_coeffs = ReformulationKit.get_variable_coefficients(coupling_mapping, JuMP.index(sp[:x][m, 2]))
        
        # Each variable should have exactly one constraint coefficient (demand constraint)
        @test length(var1_coeffs) == 1
        @test length(var2_coeffs) == 1
        
        # Each coefficient should be 1.0 for demand constraints
        @test var1_coeffs[1][3] == 1.0  # coefficient part of (type, value, coeff) tuple
        @test var2_coeffs[1][3] == 1.0
    end
end

function test_e2e_gap_with_penalties_complete_validation_ok()
    # === INLINE MODEL DECLARATION ===
    machines = 1:2
    jobs = 1:3
    
    # Problem data - small and simple for verification
    assignment_costs = [1 2 3; 4 5 6]  # machines × jobs
    penalty_costs = [10, 12, 8]        # per job (higher than assignment)
    weights = [1 1 1; 1 1 1]           # uniform weights
    capacities = [2, 2]                # tight but feasible
    
    # Build the model inline
    model = Model()
    @variable(model, x[machines, jobs], Bin)
    @variable(model, penalty[jobs] >= 0)
    @constraint(model, assignment[j in jobs], 
                sum(x[m, j] for m in machines) + penalty[j] >= 1)
    @constraint(model, capacity_constr[m in machines], 
                sum(weights[m, j] * x[m, j] for j in jobs) <= capacities[m])
    @objective(model, Min, 
               sum(assignment_costs[m, j] * x[m, j] for m in machines, j in jobs) + 
               sum(penalty_costs[j] * penalty[j] for j in jobs))
    
    # === FULL E2E WORKFLOW TEST ===
    reformulation = RK.dantzig_wolfe_decomposition(model, gap_annotation)
    
    # Test reformulation type
    @test reformulation isa RK.DantzigWolfeReformulation
    
    # === MASTER PROBLEM DEEP VALIDATION ===
    master = RK.master(reformulation)
    
    # Variable counts and structure
    @test JuMP.num_variables(master) == 3  # penalty[1], penalty[2], penalty[3]
    @test haskey(master.obj_dict, :penalty)
    @test haskey(master.obj_dict, :assignment)
    
    # Verify each penalty variable properties
    for j in jobs
        penalty_var = master[:penalty][j]
        @test JuMP.has_lower_bound(penalty_var)
        @test JuMP.lower_bound(penalty_var) == 0.0
        @test !JuMP.is_binary(penalty_var)
        @test !JuMP.is_integer(penalty_var)
        @test JuMP.owner_model(penalty_var) == master
    end
    
    # Master objective validation
    master_obj = JuMP.objective_function(master)
    @test master_obj isa JuMP.AffExpr
    @test JuMP.objective_sense(master) == MOI.MIN_SENSE
    
    # Check only master variables in master objective
    for (var, coeff) in master_obj.terms
        @test JuMP.owner_model(var) == master
        # Verify coefficient matches expected penalty cost
        if var == master[:penalty][1]
            @test coeff == penalty_costs[1]
        elseif var == master[:penalty][2]
            @test coeff == penalty_costs[2]
        elseif var == master[:penalty][3]
            @test coeff == penalty_costs[3]
        end
    end
    
    # Assignment constraints validation
    @test length(master[:assignment]) == 3  # One per job
    for j in jobs
        assignment_constr = master[:assignment][j]
        @test assignment_constr isa JuMP.ConstraintRef
    end
    
    # === SUBPROBLEMS DEEP VALIDATION ===
    subproblems = RK.subproblems(reformulation)
    @test length(subproblems) == 2  # One per machine
    
    for m in machines
        sp = subproblems[m]
        
        # Variable counts and structure
        @test JuMP.num_variables(sp) == length(jobs)  # x[m,j] for each job
        @test haskey(sp.obj_dict, :x)
        @test haskey(sp.obj_dict, :capacity_constr)
        
        # Verify each assignment variable properties
        for j in jobs
            x_var = sp[:x][m, j]
            @test JuMP.is_binary(x_var)
            @test !JuMP.is_integer(x_var)
            @test JuMP.owner_model(x_var) == sp
            # Binary variables may not have explicit bounds set
            if JuMP.has_lower_bound(x_var)
                @test JuMP.lower_bound(x_var) == 0.0
            end
            if JuMP.has_upper_bound(x_var)
                @test JuMP.upper_bound(x_var) == 1.0
            end
        end
        
        # Subproblem objective validation
        sp_obj = JuMP.objective_function(sp)
        @test sp_obj isa JuMP.AffExpr
        @test JuMP.objective_sense(sp) == MOI.MIN_SENSE
        @test !isempty(sp_obj.terms)
        
        # Check only subproblem variables in subproblem objective
        for (var, coeff) in sp_obj.terms
            @test JuMP.owner_model(var) == sp
            # Verify coefficient matches expected assignment cost
            for j in jobs
                if var == sp[:x][m, j]
                    @test coeff == assignment_costs[m, j]
                end
            end
        end
        
        # Capacity constraint validation
        capacity_constr = sp[:capacity_constr][m]
        @test capacity_constr isa JuMP.ConstraintRef
        capacity_obj = JuMP.constraint_object(capacity_constr)
        @test capacity_obj.set isa MOI.LessThan{Float64}
        @test capacity_obj.set.upper == capacities[m]
    end
    
    # === CONVEXITY CONSTRAINTS VALIDATION ===
    @test length(reformulation.convexity_constraints_lb) == 2
    @test length(reformulation.convexity_constraints_ub) == 2
    
    for m in machines
        @test haskey(reformulation.convexity_constraints_lb, m)
        @test haskey(reformulation.convexity_constraints_ub, m)
        @test reformulation.convexity_constraints_lb[m] isa JuMP.ConstraintRef
        @test reformulation.convexity_constraints_ub[m] isa JuMP.ConstraintRef
    end
    
    # === MAPPING OBJECTS DETAILED INSPECTION ===
    for m in machines
        sp = subproblems[m]
        
        # Test original cost mapping using helper methods
        cost_mapping = RK.cost_mapping(sp)
        @test ReformulationKit.get_cost(cost_mapping, JuMP.index(sp[:x][m, 1])) == Float64(assignment_costs[m, 1])
        @test ReformulationKit.get_cost(cost_mapping, JuMP.index(sp[:x][m, 2])) == Float64(assignment_costs[m, 2])
        @test ReformulationKit.get_cost(cost_mapping, JuMP.index(sp[:x][m, 3])) == Float64(assignment_costs[m, 3])
        
        # Test coupling constraint mapping structure
        coupling_mapping = RK.coupling_mapping(sp)
        @test isa(coupling_mapping, ReformulationKit.CouplingConstraintMapping)
        @test length(coupling_mapping) == 3  # Three variables with constraint coefficients
        
        # Test that we can retrieve coefficients using the new API
        var1_coeffs = ReformulationKit.get_variable_coefficients(coupling_mapping, JuMP.index(sp[:x][m, 1]))
        var2_coeffs = ReformulationKit.get_variable_coefficients(coupling_mapping, JuMP.index(sp[:x][m, 2]))
        var3_coeffs = ReformulationKit.get_variable_coefficients(coupling_mapping, JuMP.index(sp[:x][m, 3]))
        
        # Each variable should have exactly one constraint coefficient (assignment constraint)
        @test length(var1_coeffs) == 1
        @test length(var2_coeffs) == 1
        @test length(var3_coeffs) == 1
        
        # Each coefficient should be 1.0 for assignment constraints
        @test var1_coeffs[1][3] == 1.0  # coefficient part of (type, value, coeff) tuple
        @test var2_coeffs[1][3] == 1.0
        @test var3_coeffs[1][3] == 1.0
    end    
end

function test_e2e_gap_with_objective_constant_ok()
    # Test with a model that has a constant in the objective
    J = 1:2  
    M = 1:2
    c = [1 2; 3 4]
    
    model = Model()
    @variable(model, x[M, J], Bin)
    @constraint(model, cov[j in J], sum(x[m, j] for m in M) >= 1)
    @constraint(model, knp[m in M], sum(x[m, j] for j in J) <= 2)
    @objective(model, Min, sum(c[m, j] * x[m, j] for m in M, j in J) + 100)  # Add constant
    
    # Perform decomposition
    reformulation = RK.dantzig_wolfe_decomposition(model, dw_annotation)
    subproblems = RK.subproblems(reformulation)
    master = RK.master(reformulation)
    
    # Test that subproblems have zero constants in objectives
    for (m, sp) in subproblems
        sp_obj = JuMP.objective_function(sp)
        if sp_obj isa JuMP.AffExpr
            @test sp_obj.constant == 0.0  # Subproblem should have zero constant
        end
    end
    
    # Test that master preserves the constant
    master_obj = JuMP.objective_function(master)
    if master_obj isa JuMP.AffExpr
        @test master_obj.constant == 100.0  # Master should preserve constant
    end
end

function test_e2e_dantzig_wolfe_gap_scenarios()
    @testset "[e2e] basic GAP decomposition" begin
        test_e2e_basic_gap_decomposition_ok()
    end

    @testset "[e2e] GAP with penalties complete validation" begin
        test_e2e_gap_with_penalties_complete_validation_ok()
    end
    
    @testset "[e2e] GAP with objective constant" begin
        test_e2e_gap_with_objective_constant_ok()
    end
end