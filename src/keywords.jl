
function parse_kw_syntax(ps::ParseState) 
    if ps.t.kind==Tokens.BEGIN || ps.t.kind==Tokens.QUOTE   
        kw = INSTANCE(ps)
        arg = parse_block(ps)
        next(ps)
        return EXPR(kw, [arg], LOCATION(kw.loc.start, ps.t.endbyte))
    elseif ps.t.kind==Tokens.IF
        return parse_if(ps)
    elseif ps.t.kind==Tokens.TRY
        parse_try(ps)
    elseif ps.t.kind==Tokens.IMPORT || ps.t.kind==Tokens.IMPORTALL || ps.t.kind==Tokens.USING
        return parse_imports(ps)
    elseif ps.t.kind==Tokens.EXPORT
        return parse_export(ps)
    elseif Tokens.begin_0arg_kw < ps.t.kind < Tokens.end_0arg_kw
        kw = INSTANCE(ps)
        return EXPR(kw, [], LOCATION(kw.loc.start, kw.loc.stop))
    elseif Tokens.begin_1arg_kw < ps.t.kind < Tokens.end_1arg_kw
        kw = INSTANCE(ps)
        arg = parse_expression(ps)
        return EXPR(kw, [arg], LOCATION(kw.loc.start, arg.loc.stop))
    elseif Tokens.begin_2arg_kw < ps.t.kind < Tokens.end_2arg_kw
        kw = INSTANCE(ps)
        arg1 = @closer ps ws parse_expression(ps) 
        arg2 = parse_expression(ps)
        return EXPR(kw, [arg1, arg2], LOCATION(kw.loc.start, arg2.loc.stop))
    elseif Tokens.begin_3arg_kw < ps.t.kind < Tokens.end_3arg_kw
        kw = INSTANCE(ps)
        arg = @closer ps block @closer ps ws parse_expression(ps)
        block = parse_block(ps)
        next(ps)
        if kw.val=="type"
            return EXPR(kw, [TRUE, arg, block], LOCATION(kw.loc.start, block.loc.stop))
        elseif kw.val=="immutable"
            return EXPR(kw, [FALSE, arg, block], LOCATION(kw.loc.start, block.loc.stop))
        elseif kw.val=="module"
            return EXPR(kw, [TRUE, arg, block], LOCATION(kw.loc.start, block.loc.stop))
        elseif kw.val=="baremodule"
            return EXPR(kw, [FALSE, arg, block], LOCATION(kw.loc.start, block.loc.stop))
        else
            return EXPR(kw, [arg, block], LOCATION(kw.loc.start, block.loc.stop))
        end
    else
        error(ps)
    end
end

function parse_if(ps::ParseState, nested = false)
    kw = INSTANCE(ps)
    kw.val = "if"
    cond = @closer ps ws @closer ps block parse_expression(ps)
    if ps.nt.kind==Tokens.END
        next(ps)
        return EXPR(kw, [cond, EXPR(BLOCK, [], LOCATION(0, 0))], LOCATION(kw.loc.start, ps.t.endbyte))
    end
    ifblock = EXPR(BLOCK, [], LOCATION(0, 0))
    while ps.nt.kind!==Tokens.END && ps.nt.kind!==Tokens.ELSE && ps.nt.kind!==Tokens.ELSEIF
        push!(ifblock.args, @closer ps ifelse parse_expression(ps))
    end

    elseblock = EXPR(BLOCK, [], LOCATION(ps.nt.startbyte, 0))
    if ps.nt.kind==Tokens.ELSEIF
        next(ps)
        push!(elseblock.args, parse_if(ps, true))
    end
    if ps.nt.kind==Tokens.ELSE
        next(ps)
        parse_block(ps, elseblock)
    end
    
    elseblock.loc.stop = ps.nt.endbyte
    ret = isempty(elseblock.args) ? EXPR(kw, [cond, ifblock], LOCATION(kw.loc.start, ps.nt.endbyte)) : EXPR(kw, [cond, ifblock, elseblock], LOCATION(kw.loc.start, ps.nt.endbyte))
    !nested && next(ps)
    return ret
end


function parse_try(ps::ParseState)
    kw = INSTANCE(ps)
    
    tryblock = EXPR(BLOCK, [], LOCATION(0, 0))
    while ps.nt.kind!==Tokens.END && ps.nt.kind!==Tokens.CATCH 
        push!(tryblock.args, @closer ps trycatch parse_expression(ps))
    end
    next(ps)
    if ps.t.kind==Tokens.CATCH
        caught = parse_expression(ps)
        catchblock = parse_block(ps)
        if !(caught isa INSTANCE)
            unshift!(catchblock.args, caught)
            caught = FALSE
        end
    else
        caught = FALSE
        catchblock = EXPR(BLOCK, [], LOCATION(0, 0))
    end
    next(ps)
    return EXPR(kw, [tryblock, caught ,catchblock], LOCATION(kw.loc.start, ps.t.endbyte))
end

function parse_imports(ps::ParseState)
    kw = INSTANCE(ps)
    @assert ps.nt.kind == Tokens.IDENTIFIER "incomplete import statement"
    M = INSTANCE[INSTANCE(next(ps))]
    while ps.nt.kind==Tokens.DOT
        next(ps)
        @assert ps.nt.kind == Tokens.IDENTIFIER "expected only symbols in import statement"
        push!(M, INSTANCE(next(ps)))
    end
    if closer(ps)
        return EXPR(kw, M, LOCATION(kw.loc.start, last(M).loc.stop))
    else
        @assert ps.nt.kind == Tokens.COLON
        args = parse_list(ps)
        if length(args)==1
            push!(M, first(args))
            return EXPR(kw, M, LOCATION(kw.loc.start, last(args).loc.stop))
        else
            ret = EXPR(INSTANCE{KEYWORD}("toplevel", kw.ws, kw.loc, 0), [], LOCATION(kw.loc.start, last(args).loc.stop))
            for a in args
                push!(ret.args, EXPR(kw, vcat(M, a), a.loc))
            end
            return ret
        end
    end
end

function parse_export(ps::ParseState)
    kw = INSTANCE(ps)
    @assert ps.nt.kind == Tokens.IDENTIFIER "incomplete export statement"
    args = INSTANCE[INSTANCE(next(ps))]
    while ps.nt.kind==Tokens.COMMA
        next(ps)
        @assert ps.nt.kind == Tokens.IDENTIFIER "expected only symbols in import statement"
        push!(args, INSTANCE(next(ps)))
    end

    return EXPR(kw, args, LOCATION(kw.loc.start, last(args).loc.stop))
end