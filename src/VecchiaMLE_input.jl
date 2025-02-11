function VecchiaMLE_Run(iVecchiaMLE::VecchiaMLEInput)

    sanitize_input!(iVecchiaMLE)

    pres_chol = Matrix{eltype(iVecchiaMLE.samples)}(undef, iVecchiaMLE.n^2, iVecchiaMLE.n^2)
    fill!(pres_chol, zero(eltype(iVecchiaMLE.samples)))
    diagnostics = Diagnostics(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0)
    VecchiaMLE_Run_Analysis!(iVecchiaMLE, pres_chol, diagnostics)
    
    return diagnostics, pres_chol
end

function VecchiaMLE_Run_Analysis!(iVecchiaMLE::VecchiaMLEInput, pres_chol::AbstractMatrix, diagnostics::Diagnostics)
    model, output = ExecuteModel!(iVecchiaMLE, pres_chol, diagnostics)

    # TODO: NEEDS TO BE IMPLEMENTED
    diagnostics.LinAlg_solve_time = output.counters.linear_solver_time
    diagnostics.MadNLP_iterations = output.iter
    diagnostics.mode = iVecchiaMLE.mode

    # Getting some values for error checking
    diagnostics.objective_value = NLPModels.obj(model, output.solution)
    cons_vec = typeof(output.solution)(undef, model.cache.n)
    NLPModels.cons!(model, output.solution, cons_vec)

    grad_vec = typeof(output.solution)(undef, length(output.solution))
    fill!(grad_vec, 0.0)
    NLPModels.grad!(model, output.solution, grad_vec)
    Jtv = similar(grad_vec)
    NLPModels.jtprod!(model, output.solution, output.multipliers, Jtv)
    grad_vec .+= Jtv

    diagnostics.normed_constraint_value = norm(cons_vec)
    diagnostics.normed_grad_value = norm(grad_vec)
end


function ExecuteModel!(iVecchiaMLE::VecchiaMLEInput, pres_chol::AbstractMatrix, diags::Diagnostics)
    # TODO: Enable xyGrid as input, only defaulting to this.
    xyGrid = generate_xyGrid(iVecchiaMLE.n)

    diags.create_model_time = @elapsed begin
        if COMPUTE_MODE(iVecchiaMLE.mode) == CPU
            model = VecchiaModelCPU(iVecchiaMLE.samples, iVecchiaMLE.k, xyGrid)
        elseif COMPUTE_MODE(iVecchiaMLE.mode) == GPU
            model = VecchiaModelGPU(iVecchiaMLE.samples, iVecchiaMLE.k, xyGrid)
        else
            @warn "Model Not Made!"     
        end
    end
    
    diags.solve_model_time = @elapsed begin
        output = madnlp(model, print_level=MadNLP_Print_Level(iVecchiaMLE.MadNLP_print_level))
    end
    
    
    # Casting to CPU matrices
    valsL = Vector{Float64}(output.solution[1:model.cache.nnzL])
    rowsL = Vector{Int}(model.cache.rowsL)
    colsL = Vector{Int}(model.cache.colsL)
    copyto!(pres_chol, LowerTriangular(sparse(rowsL, colsL, valsL)))
    return model, output
end