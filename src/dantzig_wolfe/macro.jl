# Copyright (c) 2025 Nablarise. All rights reserved.
# Author: Guillaume Marques <guillaume@nablarise.com>
# SPDX-License-Identifier: Proprietary

struct SubproblemAssignment
    id_expr::Any
end

struct MasterAssignment
end

struct PatternRule
    name::Symbol
    indices::Vector{Symbol}
    assignment::Union{SubproblemAssignment, MasterAssignment}
end


"""
    @dantzig_wolfe model begin
        pattern => assignment
        ...
    end

Macro for declarative Dantzig-Wolfe decomposition specification.

# Pattern Syntax
- `constraint_name[index1, index2, ...]` - constraint or variable pattern
- `_` - wildcard for ignored indices  
- `variable_name` - captured index used in assignment

# Assignment Syntax
- `subproblem(id)` - assign to subproblem with given ID
- `master()` - assign to master problem

# Example
```julia
@dantzig_wolfe model begin
    assignment[m, _] => subproblem(m)     # assignment constraint to subproblem m
    knapsack[m] => subproblem(m)          # knapsack constraint to subproblem m  
    coverage[_] => master()               # coverage constraint to master
end
```

This generates an annotation function and calls `dantzig_wolfe_decomposition(model, annotation_fn)`.
"""
macro dantzig_wolfe(model, block)
    patterns = parse_block(block)
    fn_name = gensym("generated_annotation")
    method_defs = generate_method_definitions(fn_name, patterns)
    
    return quote
        $(method_defs...)
        dantzig_wolfe_decomposition($(esc(model)), $fn_name)
    end
end

function parse_block(block::Expr)
    if block.head != :block
        error("Expected begin...end block")
    end
    
    patterns = PatternRule[]
    for line in block.args
        if line isa LineNumberNode
            continue
        end
        
        if line isa Expr && line.head == :call && length(line.args) == 3 && line.args[1] == :(=>)
            pattern, assignment = line.args[2], line.args[3]
            push!(patterns, parse_pattern_rule(pattern, assignment))
        else
            error("Expected pattern => assignment, got: $line")
        end
    end
    
    if isempty(patterns)
        error("No patterns specified in @dantzig_wolfe block")
    end
    
    return patterns
end

function parse_pattern_rule(pattern, assignment::Expr)
    name, indices = parse_pattern(pattern)
    assign = parse_assignment(assignment)
    return PatternRule(name, indices, assign)
end

function parse_pattern(pattern)
    if pattern isa Symbol
        # Handle patterns without indices like: x => subproblem(1)
        return pattern, Symbol[]
    elseif pattern isa Expr && pattern.head == :ref
        name = pattern.args[1]
        if !(name isa Symbol)
            error("Pattern name must be a symbol, got: $name")
        end
        indices = pattern.args[2:end]
        
        index_symbols = Symbol[]
        for idx in indices
            if idx isa Symbol
                push!(index_symbols, idx)
            else
                error("Index must be a symbol or _, got: $idx")
            end
        end
        
        return name, index_symbols
    else
        error("Expected pattern[indices] or pattern, got: $pattern")
    end
end

function parse_assignment(assignment::Expr)
    if assignment.head == :call
        func_name = assignment.args[1]
        
        if func_name == :subproblem
            if length(assignment.args) != 2
                error("subproblem() requires exactly one argument")
            end
            id_expr = assignment.args[2]
            return SubproblemAssignment(id_expr)
            
        elseif func_name == :master
            if length(assignment.args) != 1
                error("master() takes no arguments")
            end
            return MasterAssignment()
        else
            error("Unknown assignment function: $func_name")
        end
    else
        error("Expected function call for assignment, got: $assignment")
    end
end

function generate_method_definitions(fn_name::Symbol, patterns::Vector{PatternRule})
    method_defs = Expr[]
    
    for pattern in patterns
        method_def = generate_method_definition(fn_name, pattern)
        push!(method_defs, method_def)
    end
    
    return method_defs
end

function generate_method_definition(fn_name::Symbol, pattern::PatternRule)
    # Create the Val type parameter
    val_param = :(::Val{$(QuoteNode(pattern.name))})
    
    # Create the parameter list: (::Val{:name}, indices...)
    if isempty(pattern.indices)
        params = [val_param]
    else
        params = [val_param, pattern.indices...]
    end
    
    # Generate the assignment expression
    assignment_expr = generate_assignment_expr(pattern.assignment)
    
    # Create the method definition
    return :(function $fn_name($(params...))
        $assignment_expr
    end)
end

function generate_assignment_expr(assignment::SubproblemAssignment)
    return :(dantzig_wolfe_subproblem($(assignment.id_expr)))
end

function generate_assignment_expr(::MasterAssignment)
    return :(dantzig_wolfe_master())
end