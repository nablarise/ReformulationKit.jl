struct DantzigWolfeReformulation
    master_problem::Model
    subproblems::Dict{Any,Model} # subproblem_id => JuMP model
    convexity_constraints_lb::Dict{Any,Any} # subproblem_id => JuMP constraint
    convexity_constraints_ub::Dict{Any,Any}
end

master(reformulation::DantzigWolfeReformulation) = reformulation.master_problem
subproblems(reformulation::DantzigWolfeReformulation) = reformulation.subproblems