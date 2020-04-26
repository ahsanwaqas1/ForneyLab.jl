import Base: split

export
ruleSPNonlinearUTOutNG,
ruleSPNonlinearUTOutNGX,
ruleSPNonlinearUTIn1GG,
ruleSPNonlinearUTInGX,
ruleSPNonlinearLInMN,
ruleSPNonlinearLOutNG,
ruleSPNonlinearLOutNB,
ruleSPNonlinearLOutNC,
ruleSPNonlinearLOutNLn,
ruleSPNonlinearLOutNGamma,
ruleSPNonlinearLOutNBeta,
ruleSPNonlinearLOutNP,
ruleSPNonlinearLOutND,
ruleMNonlinearUTNGX,
prod!

const default_alpha = 1e-3 # Default value for the spread parameter
const default_beta = 2.0
const default_kappa = 0.0

"""
Return the sigma points and weights for a Gaussian distribution
"""
function sigmaPointsAndWeights(m::Float64, V::Float64; alpha=default_alpha, beta=default_beta, kappa=default_kappa)
    lambda = (1 + kappa)*alpha^2 - 1

    sigma_points = Vector{Float64}(undef, 3)
    weights_m = Vector{Float64}(undef, 3)
    weights_c = Vector{Float64}(undef, 3)

    l = sqrt((1 + lambda)*V)

    sigma_points[1] = m
    sigma_points[2] = m + l
    sigma_points[3] = m - l
    weights_m[1] = lambda/(1 + lambda)
    weights_m[2] = weights_m[3] = 1/(2*(1 + lambda))
    weights_c[1] = weights_m[1] + (1 - alpha^2 + beta)
    weights_c[2] = weights_c[3] = 1/(2*(1 + lambda))

    return (sigma_points, weights_m, weights_c)
end

function sigmaPointsAndWeights(m::Vector{Float64}, V::AbstractMatrix; alpha=default_alpha, beta=default_beta, kappa=default_kappa)
    d = length(m)
    lambda = (d + kappa)*alpha^2 - d

    sigma_points = Vector{Vector{Float64}}(undef, 2*d+1)
    weights_m = Vector{Float64}(undef, 2*d+1)
    weights_c = Vector{Float64}(undef, 2*d+1)

    if isa(V, Diagonal)
        L = sqrt((d + lambda)*V) # Matrix square root
    else
        L = sqrt(Hermitian((d + lambda)*V))
    end

    sigma_points[1] = m
    weights_m[1] = lambda/(d + lambda)
    weights_c[1] = weights_m[1] + (1 - alpha^2 + beta)
    for i = 1:d
        sigma_points[2*i] = m + L[:,i]
        sigma_points[2*i+1] = m - L[:,i]
    end
    weights_m[2:end] .= 1/(2*(d + lambda))
    weights_c[2:end] .= 1/(2*(d + lambda))

    return (sigma_points, weights_m, weights_c)
end

"""
Return the statistics for the unscented approximation to the forward joint
"""
function unscentedStatistics(m::Float64, V::Float64, g::Function; alpha=default_alpha, beta=default_beta, kappa=default_kappa)
    (sigma_points, weights_m, weights_c) = sigmaPointsAndWeights(m, V; alpha=alpha, beta=beta, kappa=kappa)

    g_sigma = g.(sigma_points)
    m_tilde = sum(weights_m.*g_sigma)
    V_tilde = sum(weights_c.*(g_sigma .- m_tilde).^2)
    C_tilde = sum(weights_c.*(sigma_points .- m).*(g_sigma .- m_tilde))

    return (m_tilde, V_tilde, C_tilde)
end

# Multiple univariate inbounds
function unscentedStatistics(ms::Vector{Float64}, Vs::Vector{Float64}, g::Function; alpha=default_alpha, beta=default_beta, kappa=default_kappa)
    (m, V, ds) = concatenateGaussianMV(ms, Vs)
    (sigma_points, weights_m, weights_c) = sigmaPointsAndWeights(m, V; alpha=alpha, beta=beta, kappa=kappa)

    g_sigma = [g(sp...) for sp in sigma_points] # Unpack each sigma point in g

    d = sum(ds) # Dimensionality of joint
    m_tilde = sum(weights_m.*g_sigma) # Scalar
    V_tilde = sum(weights_c.*(g_sigma .- m_tilde).^2) # Scalar
    C_tilde = sum([weights_c[k+1]*(sigma_points[k+1] - ms)*(g_sigma[k+1] - m_tilde) for k=0:2*d]) # Vector

    return (m_tilde, V_tilde, C_tilde)
end

# Single multivariate inbound
function unscentedStatistics(m::Vector{Float64}, V::AbstractMatrix, g::Function; alpha=default_alpha, beta=default_beta, kappa=default_kappa)
    (sigma_points, weights_m, weights_c) = sigmaPointsAndWeights(m, V; alpha=alpha, beta=beta, kappa=kappa)
    d = length(m)

    g_sigma = g.(sigma_points)
    m_tilde = sum([weights_m[k+1]*g_sigma[k+1] for k=0:2*d])
    V_tilde = sum([weights_c[k+1]*(g_sigma[k+1] - m_tilde)*(g_sigma[k+1] - m_tilde)' for k=0:2*d])
    C_tilde = sum([weights_c[k+1]*(sigma_points[k+1] - m)*(g_sigma[k+1] - m_tilde)' for k=0:2*d])

    return (m_tilde, V_tilde, C_tilde)
end

# Multiple multivariate inbounds
function unscentedStatistics(ms::Vector{Vector{Float64}}, Vs::Vector{<:AbstractMatrix}, g::Function; alpha=default_alpha, beta=default_beta, kappa=default_kappa)
    (m, V, ds) = concatenateGaussianMV(ms, Vs)
    (sigma_points, weights_m, weights_c) = sigmaPointsAndWeights(m, V; alpha=alpha, beta=beta, kappa=kappa)

    g_sigma = [g(split(sp, ds)...) for sp in sigma_points] # Unpack each sigma point in g

    d = sum(ds) # Dimensionality of joint
    m_tilde = sum([weights_m[k+1]*g_sigma[k+1] for k=0:2*d]) # Vector
    V_tilde = sum([weights_c[k+1]*(g_sigma[k+1] - m_tilde)*(g_sigma[k+1] - m_tilde)' for k=0:2*d]) # Matrix
    C_tilde = sum([weights_c[k+1]*(sigma_points[k+1] - m)*(g_sigma[k+1] - m_tilde)' for k=0:2*d]) # Matrix

    return (m_tilde, V_tilde, C_tilde)
end

"""
RTS smoother update, based on (Petersen et al. 2018; On Approximate Nonlinear Gaussian Message Passing on Factor Graphs)
Note, this implementation is not as efficient as Petersen et al. (2018), because we explicitly require the outbound messages
"""
function smoothRTS(m_tilde, V_tilde, C_tilde, m_fw_in, V_fw_in, m_bw_out, V_bw_out)
    C_tilde_inv = pinv(C_tilde)
    V_bw_in = V_fw_in*C_tilde_inv'*(V_tilde + V_bw_out)*C_tilde_inv*V_fw_in - V_fw_in
    m_bw_in = m_fw_in + V_fw_in*C_tilde_inv'*(m_bw_out - m_tilde)

    return (m_bw_in, V_bw_in)
end

#-------------
# Update Rules
#-------------

# Forward rule (unscented transform)
function ruleSPNonlinearUTOutNG(g::Function,
                                msg_out::Nothing,
                                msg_in1::Message{F, V};
                                alpha::Float64=default_alpha) where {F<:Gaussian, V<:VariateType}

    (m_fw_in1, V_fw_in1) = unsafeMeanCov(msg_in1.dist)
    (m_tilde, V_tilde, _) = unscentedStatistics(m_fw_in1, V_fw_in1, g; alpha=alpha)

    return Message(V, GaussianMeanVariance, m=m_tilde, v=V_tilde)
end

# Multi-argument forward rule (unscented transform)
function ruleSPNonlinearUTOutNGX(g::Function, # Needs to be in front of Vararg
                                 msg_out::Nothing,
                                 msgs_in::Vararg{Message{<:Gaussian, V}};
                                 alpha::Float64=default_alpha) where V<:VariateType

    (ms_fw_in, Vs_fw_in) = collectStatistics(msgs_in...) # Returns arrays with individual means and covariances
    (m_tilde, V_tilde, _) = unscentedStatistics(ms_fw_in, Vs_fw_in, g; alpha=alpha)

    return Message(V, GaussianMeanVariance, m=m_tilde, v=V_tilde)
end

# Backward rule with given inverse (unscented transform)
function ruleSPNonlinearUTIn1GG(g::Function,
                                g_inv::Function,
                                msg_out::Message{F, V},
                                msg_in1::Nothing;
                                alpha::Float64=default_alpha) where {F<:Gaussian, V<:VariateType}

    (m_bw_out, V_bw_out) = unsafeMeanCov(msg_out.dist)
    (m_tilde, V_tilde, _) = unscentedStatistics(m_bw_out, V_bw_out, g_inv; alpha=alpha)

    return Message(V, GaussianMeanVariance, m=m_tilde, v=V_tilde)
end

# Multi-argument backward rule with given inverse (unscented transform)
function ruleSPNonlinearUTInGX(g::Function, # Needs to be in front of Vararg
                               g_inv::Function,
                               msg_out::Message{<:Gaussian, V},
                               msgs_in::Vararg{Union{Message{<:Gaussian, V}, Nothing}};
                               alpha::Float64=default_alpha) where V<:VariateType

    (ms, Vs) = collectStatistics(msg_out, msgs_in...) # Returns arrays with individual means and covariances
    (m_tilde, V_tilde, _) = unscentedStatistics(ms, Vs, g_inv; alpha=alpha)

    return Message(V, GaussianMeanVariance, m=m_tilde, v=V_tilde)
end

# Backward rule with unknown inverse (unscented transform)
function ruleSPNonlinearUTIn1GG(g::Function,
                                msg_out::Message{F1, V},
                                msg_in1::Message{F2, V};
                                alpha::Float64=default_alpha) where {F1<:Gaussian, F2<:Gaussian, V<:VariateType}

    (m_fw_in1, V_fw_in1) = unsafeMeanCov(msg_in1.dist)
    (m_tilde, V_tilde, C_tilde) = unscentedStatistics(m_fw_in1, V_fw_in1, g; alpha=alpha)

    # RTS smoother
    W_fw_in1 = unsafePrecision(msg_in1.dist)
    (m_bw_out, V_bw_out) = unsafeMeanCov(msg_out.dist)
    (m_bw_in1, V_bw_in1) = smoothRTS(m_tilde, V_tilde, C_tilde, m_fw_in1, V_fw_in1, m_bw_out, V_bw_out)

    return Message(V, GaussianMeanVariance, m=m_bw_in1, v=V_bw_in1)
end

# Multi-argument backward rule with unknown inverse (unscented transform)
function ruleSPNonlinearUTInGX(g::Function,
                               inx::Int64, # Index of inbound interface inx
                               msg_out::Message{<:Gaussian, V},
                               msgs_in::Vararg{Message{<:Gaussian, V}};
                               alpha::Float64=default_alpha) where V<:VariateType

    # Approximate joint inbounds
    (ms_fw_in, Vs_fw_in) = collectStatistics(msgs_in...) # Returns arrays with individual means and covariances
    (m_tilde, V_tilde, C_tilde) = unscentedStatistics(ms_fw_in, Vs_fw_in, g; alpha=alpha)

    # RTS smoother
    (m_fw_in, V_fw_in, ds) = concatenateGaussianMV(ms_fw_in, Vs_fw_in)
    W_fw_in = cholinv(V_fw_in)
    (m_bw_out, V_bw_out) = unsafeMeanCov(msg_out.dist)
    (m_bw_in, V_bw_in) = smoothRTS(m_tilde, V_tilde, C_tilde, m_fw_in, V_fw_in, m_bw_out, V_bw_out)

    # Marginalize
    (m_bw_inx, V_bw_inx) = marginalizeGaussianMV(V, m_bw_in, V_bw_in, ds, inx)

    return Message(V, GaussianMeanVariance, m=m_bw_inx, v=V_bw_inx)
end

function ruleMNonlinearUTNGX(g::Function,
                             msg_out::Message{<:Gaussian, V},
                             msgs_in::Vararg{Message{<:Gaussian, V}};
                             alpha::Float64=default_alpha) where V<:VariateType

    # Approximate joint inbounds
    (ms_fw_in, Vs_fw_in) = collectStatistics(msgs_in...) # Returns arrays with individual means and covariances
    (m_tilde, V_tilde, C_tilde) = unscentedStatistics(ms_fw_in, Vs_fw_in, g; alpha=alpha)

    (_, V_fw_in, _) = concatenateGaussianMV(ms_fw_in, Vs_fw_in) # Statistics of joint forward messages
    (m_bw_out, V_bw_out) = unsafeMeanCov(msg_out.dist)

    # Compute joint marginal on ins; based on (Petersen et al. 2018; On Approximate Nonlinear Gaussian Message Passing on Factor Graphs)
    P = cholinv(V_tilde + V_bw_out)
    W_tilde = cholinv(V_tilde)
    V_in = V_fw_in + C_tilde*W_tilde*V_bw_out*P*C_tilde' - C_tilde*W_tilde*C_tilde'
    m_out = V_tilde*P*m_bw_out + V_bw_out*P*m_tilde
    m_in = C_tilde*W_tilde*(m_out - m_tilde)

    return ProbabilityDistribution(Multivariate, GaussianMeanVariance, m=m_in, v=V_in)
end


#---------------------------
# Custom inbounds collectors
#---------------------------

# Unscented transform
function collectSumProductNodeInbounds(node::Nonlinear{Unscented}, entry::ScheduleEntry)
    inbounds = Any[]

    # Push function (and inverse) to calling signature
    # These functions needs to be defined in the scope of the user
    push!(inbounds, Dict{Symbol, Any}(:g => node.g,
                                      :keyword => false))

    multi_in = (length(node.interfaces) > 2) # Boolean to indicate a multi-inbound nonlinear node
    inx = findfirst(isequal(entry.interface), node.interfaces) - 1 # Find number of inbound interface; 0 for outbound
    undefined_inverse = (node.g_inv == nothing) || (multi_in && (inx > 0) && (node.g_inv[inx] == nothing))

    if inx > 0 # A backward message is required
        if multi_in && undefined_inverse # Multi-inbound with undefined inverse
            push!(inbounds, Dict{Symbol, Any}(:inx => inx, # Push inbound identifier
                                              :keyword => false))
        elseif multi_in && !undefined_inverse # Multi-inbound with defined specific inverse
            push!(inbounds, Dict{Symbol, Any}(:g_inv => node.g_inv[inx], # Push corresponding inverse
                                              :keyword => false))
        elseif !multi_in && !undefined_inverse # Single-inbound with defined inverse
            push!(inbounds, Dict{Symbol, Any}(:g_inv => node.g_inv, # Push inverse
                                              :keyword => false))
        end # Single-inbound with undefined inverse does not push inbound
    end

    interface_to_schedule_entry = current_inference_algorithm.interface_to_schedule_entry
    for node_interface in node.interfaces
        inbound_interface = ultimatePartner(node_interface)
        if (node_interface == entry.interface != node.interfaces[1]) && undefined_inverse
            # Collect the message inbound if no inverse is available for backward rule
            haskey(interface_to_schedule_entry, inbound_interface) || error("The nonlinear node's backward rule uses the incoming message on the input edge to determine the approximation point. Try altering the variable order in the scheduler to first perform a forward pass.")
            push!(inbounds, interface_to_schedule_entry[inbound_interface])
        elseif node_interface == entry.interface
            # Ignore inbound message on outbound interface
            push!(inbounds, nothing)
        elseif isa(inbound_interface.node, Clamp)
            # Hard-code outbound message of constant node in schedule
            push!(inbounds, assembleClamp!(inbound_interface.node, Message))
        else
            # Collect message from previous result
            push!(inbounds, interface_to_schedule_entry[inbound_interface])
        end
    end

    # Push spread parameter if manually defined
    if node.alpha != nothing
        push!(inbounds, Dict{Symbol, Any}(:alpha => node.alpha,
                                          :keyword => true))
    end

    return inbounds
end

function ruleSPNonlinearLInMN(msg_out::Message{F, Univariate}, msg_in1::Nothing, g::Function) where {F<:SoftFactor}
    try
        ForwardDiff.derivative(g, 0)
        return Message(Univariate, Function, log_pdf=(z) -> logPdf(msg_out.dist, g(z)), ApproximationType="NonlinearL")
    catch
        return Message(Multivariate, Function, log_pdf=(z) -> logPdf(msg_out.dist, g(z)), ApproximationType="NonlinearL")
    end
end

function ruleSPNonlinearLInMN(msg_out::Message{F, Multivariate}, msg_in1::Nothing, g::Function) where {F<:SoftFactor}
    try
        ForwardDiff.derivative(g, 0)
        return Message(Univariate, Function, log_pdf=(z) -> logPdf(msg_out.dist, g(z)), ApproximationType="NonlinearL")
    catch
        return Message(Multivariate, Function, log_pdf=(z) -> logPdf(msg_out.dist, g(z)), ApproximationType="NonlinearL")
    end
end

function ruleSPNonlinearLOutNG(msg_out::Nothing, msg_in1::Message{F, Univariate}, g::Function, n_samples::Int) where {F<:Gaussian}
    # The forward message is parameterized by a SampleList
    dist_in1 = convert(ProbabilityDistribution{Univariate, GaussianMeanVariance}, msg_in1.dist)

    sample_list = g.(dist_in1.params[:m] .+ sqrt(dist_in1.params[:v]).*randn(n_samples))

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end

end

function ruleSPNonlinearLOutNG(msg_out::Nothing, msg_in1::Message{F, Multivariate}, g::Function, n_samples::Int) where {F<:Gaussian}
    # The forward message is parameterized by a SampleList
    dist_in1 = convert(ProbabilityDistribution{Multivariate, GaussianMeanVariance}, msg_in1.dist)

    CL = cholesky(dist_in1.params[:v]).L
    dim = dims(dist_in1)
    sample_list = []
    for j=1:n_samples
        sample = g(dist_in1.params[:m] + CL*randn(dim))
        push!(sample_list,sample)
    end

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end

end

function ruleSPNonlinearLOutNB(msg_out::Nothing, msg_in1::Message{Bernoulli, Univariate}, g::Function, n_samples::Int)
    # The forward message is parameterized by a SampleList
    sample_list = []
    for i=1:n_samples
        push!(sample_list,g(sample(msg_in1.dist)))
    end

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end
end

function ruleSPNonlinearLOutNC(msg_out::Nothing, msg_in1::Message{Categorical, Univariate}, g::Function, n_samples::Int)
    # The forward message is parameterized by a SampleList
    sample_list = []
    for i=1:n_samples
        push!(sample_list,g(sample(msg_in1.dist)))
    end

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end
end

function ruleSPNonlinearLOutNLn(msg_out::Nothing, msg_in1::Message{LogNormal, Univariate}, g::Function, n_samples::Int)
    # The forward message is parameterized by a SampleList
    sample_list = []
    for i=1:n_samples
        push!(sample_list,g(sample(msg_in1.dist)))
    end

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end
end

function ruleSPNonlinearLOutNGamma(msg_out::Nothing, msg_in1::Message{Gamma, Univariate}, g::Function, n_samples::Int)
    # The forward message is parameterized by a SampleList
    sample_list = []
    for i=1:n_samples
        push!(sample_list,g(sample(msg_in1.dist)))
    end

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end
end

function ruleSPNonlinearLOutNBeta(msg_out::Nothing, msg_in1::Message{Beta, Univariate}, g::Function, n_samples::Int)
    # The forward message is parameterized by a SampleList
    sample_list = []
    for i=1:n_samples
        push!(sample_list,g(sample(msg_in1.dist)))
    end

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end
end

function ruleSPNonlinearLOutNP(msg_out::Nothing, msg_in1::Message{Poisson, Univariate}, g::Function, n_samples::Int)
    # The forward message is parameterized by a SampleList
    sample_list = []
    for i=1:n_samples
        push!(sample_list,g(sample(msg_in1.dist)))
    end

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end
end

function ruleSPNonlinearLOutND(msg_out::Nothing, msg_in1::Message{Dirichlet, Univariate}, g::Function, n_samples::Int)
    # The forward message is parameterized by a SampleList
    sample_list = []
    for i=1:n_samples
        push!(sample_list,g(sample(msg_in1.dist)))
    end

    weight_list = ones(n_samples)/n_samples

    if length(sample_list[1]) == 1
        return Message(Univariate, SampleList, s=sample_list, w=weight_list)
    else
        return Message(Multivariate, SampleList, s=sample_list, w=weight_list)
    end
end

@symmetrical function prod!(
    x::ProbabilityDistribution{Univariate, Function},
    y::ProbabilityDistribution{Univariate, F},
    z::ProbabilityDistribution{Univariate, GaussianMeanVariance}=ProbabilityDistribution(Univariate, GaussianMeanVariance, m=0.0, v=1.0)) where {F<:Gaussian}

    if x.params[:ApproximationType] == "NonlinearL"
        # The product of a log-pdf and Gaussian distribution is approximated by Sampling method
        y = convert(ProbabilityDistribution{Univariate, GaussianMeanVariance}, y)
        log_joint(s) = logPdf(y,s) + x.params[:log_pdf](s)
        #Optimization with gradient ascent
        d_log_joint(s) = ForwardDiff.derivative(log_joint, s)
        m_old = y.params[:m] #initial point
        step_size = 0.01 #initial step size
        satisfied = 0
        step_count = 0
        m_total = 0.0
        m_average = 0.0
        m_new = 0.0
        while satisfied == 0
            m_new = m_old + step_size*d_log_joint(m_old)
            if log_joint(m_new) > log_joint(m_old)
                proposal_step_size = 10*step_size
                m_proposal = m_old + proposal_step_size*d_log_joint(m_old)
                if log_joint(m_proposal) > log_joint(m_new)
                    m_new = m_proposal
                    step_size = proposal_step_size
                end
            else
                step_size = 0.1*step_size
                m_new = m_old + step_size*d_log_joint(m_old)
            end
            step_count += 1
            m_total += m_old
            m_average = m_total / step_count
            if step_count > 10
                if abs((m_new-m_average)/m_average) < 0.1
                    satisfied = 1
                end
            elseif step_count > 250
                satisfied = 1
            end
            m_old = m_new
        end
        mean = m_new
        var = - 1.0 / ForwardDiff.derivative(d_log_joint, mean)

        z.params[:m] = mean
        z.params[:v] = var
    end
    if x.params[:ApproximationType] == "BivariateL"
        z.params[:m] = x.params[:m]
        z.params[:v] = x.params[:v]
    end

    return z
end

@symmetrical function prod!(
    x::ProbabilityDistribution{Multivariate, Function},
    y::ProbabilityDistribution{Multivariate, F},
    z::ProbabilityDistribution{Multivariate, GaussianMeanVariance}=ProbabilityDistribution(Multivariate, GaussianMeanVariance, m=[0.0], v=mat(1.0))) where {F<:Gaussian}

    if x.params[:ApproximationType] == "NonlinearL"
        # The product of a log-pdf and Gaussian distribution is approximated by Sampling method
        y = convert(ProbabilityDistribution{Multivariate, GaussianMeanVariance}, y)
        dim = dims(y)
        log_joint(s) = logPdf(y,s) + x.params[:log_pdf](s)
        #Optimization with gradient ascent
        d_log_joint(s) = ForwardDiff.gradient(log_joint, s)
        m_initial = y.params[:m] #initial point
        gradientOptimization(log_joint, d_log_joint, m_initial, 0.01)
        mean = m_new
        var = inv(- 1.0 .* ForwardDiff.jacobian(d_log_joint, mean))

        z.params[:m] = mean
        z.params[:v] = var
    end
    if x.params[:ApproximationType] == "BivariateL"
        z.params[:m] = x.params[:m]
        z.params[:v] = x.params[:v]
    end

    return z
end

# Think more carefully about the prod of function messages
function prod!(
    x::ProbabilityDistribution{Univariate, Function},
    y::ProbabilityDistribution{Univariate, Function},
    z::ProbabilityDistribution{Univariate, Function}=ProbabilityDistribution(Univariate, Function, log_pdf=(s)->s, ApproximationType="NonlinearL"))

    z.params[:log_pdf] = ((s) -> x.params[:log_pdf](s) + y.params[:log_pdf](s))
    if x.params[:ApproximationType] == y.params[:ApproximationType]
        z.params[:ApproximationType] = x.params[:ApproximationType]
    else
        z.params[:ApproximationType] = "NonlinearL"
    end

    return z
end

function prod!(
    x::ProbabilityDistribution{Multivariate, Function},
    y::ProbabilityDistribution{Multivariate, Function},
    z::ProbabilityDistribution{Multivariate, Function}=ProbabilityDistribution(Multivariate, Function, log_pdf=(s)->s, ApproximationType="NonlinearL"))

    z.params[:log_pdf] = ((s) -> x.params[:log_pdf](s) + y.params[:log_pdf](s))
    if x.params[:ApproximationType] == y.params[:ApproximationType]
        z.params[:ApproximationType] = x.params[:ApproximationType]
    else
        z.params[:ApproximationType] = "NonlinearL"
    end

    return z
end

# Unscented transform
function collectMarginalNodeInbounds(node::Nonlinear{Unscented}, entry::MarginalEntry)
    inbounds = Any[]

    # Push function (and inverse) to calling signature
    # These functions needs to be defined in the scope of the user
    push!(inbounds, Dict{Symbol, Any}(:g => node.g,
                                      :keyword => false))

    interface_to_schedule_entry = current_inference_algorithm.interface_to_schedule_entry
    target_to_marginal_entry = current_inference_algorithm.target_to_marginal_entry
    inbound_cluster = entry.target # Entry target is a cluster

    entry_pf = posteriorFactor(first(entry.target.edges))
    encountered_external_regions = Set{Region}()
    for node_interface in entry.target.node.interfaces
        current_region = region(inbound_cluster.node, node_interface.edge) # Note: edges that are not assigned to a posterior factor are assumed mean-field
        current_pf = posteriorFactor(node_interface.edge) # Returns an Edge if no posterior factor is assigned
        inbound_interface = ultimatePartner(node_interface)

        if (inbound_interface != nothing) && isa(inbound_interface.node, Clamp)
            # Edge is clamped, hard-code marginal of constant node
            push!(inbounds, assembleClamp!(copy(inbound_interface.node), ProbabilityDistribution)) # Copy Clamp before assembly to prevent overwriting dist_or_msg field
        elseif (current_pf === entry_pf)
            # Edge is internal, collect message from previous result
            push!(inbounds, interface_to_schedule_entry[inbound_interface])
        elseif !(current_region in encountered_external_regions)
            # Edge is external and region is not yet encountered, collect marginal from marginal dictionary
            push!(inbounds, target_to_marginal_entry[current_region])
            push!(encountered_external_regions, current_region) # Register current region with encountered external regions
        end
    end

    return inbounds
end

function collectSumProductNodeInbounds(node::Nonlinear{Sampling}, entry::ScheduleEntry)
    interface_to_schedule_entry = current_inference_algorithm.interface_to_schedule_entry

    inbounds = Any[]
    for node_interface in node.interfaces
        inbound_interface = ultimatePartner(node_interface)
        if node_interface == entry.interface
            # Ignore inbound message on outbound interface
            push!(inbounds, nothing)
        elseif isa(inbound_interface.node, Clamp)
            # Hard-code outbound message of constant node in schedule
            push!(inbounds, assembleClamp!(inbound_interface.node, Message))
        else
            # Collect message from previous result
            push!(inbounds, interface_to_schedule_entry[inbound_interface])
        end
    end

    # Push function (and inverse) to calling signature
    # These functions needs to be defined in the scope of the user
    push!(inbounds, Dict{Symbol, Any}(:g => node.g,
                                      :keyword => false))
    
    # Push n_samples argument only for rules that do sampling
    if entry.message_update_rule in Set([SPNonlinearLOutNG, SPNonlinearLOutNB, SPNonlinearLOutNC, SPNonlinearLOutNLn, SPNonlinearLOutNGamma, SPNonlinearLOutNBeta, SPNonlinearLOutNP, SPNonlinearLOutND])
        push!(inbounds, node.n_samples)
    end
    return inbounds
end

#--------
# Helpers
#--------

"""
Collect the statistics of separate Gaussian messages
"""
function collectStatistics(msgs::Vararg{Union{Message{<:Gaussian}, Nothing}})
    stats = []
    for msg in msgs
        (msg == nothing) && continue # Skip unreported messages
        push!(stats, unsafeMeanCov(msg.dist))
    end

    ms = [stat[1] for stat in stats]
    Vs = [stat[2] for stat in stats]

    return (ms, Vs) # Return tuple with vectors for means and covariances
end

"""
Return the marginalized statistics of the Gaussian corresponding to an inbound inx
"""
marginalizeGaussianMV(T::Type{<:Univariate}, m::Vector{Float64}, V::AbstractMatrix, ds::Vector{Int64}, inx::Int64) = (m[inx], V[inx, inx])

function marginalizeGaussianMV(T::Type{<:Multivariate}, m::Vector{Float64}, V::AbstractMatrix, ds::Vector{Int64}, inx::Int64)
    ds_start = cumsum([1; ds]) # Starting indices
    d_start = ds_start[inx]
    d_end = ds_start[inx + 1] - 1
    mx = m[d_start:d_end] # Vector
    Vx = V[d_start:d_end, d_start:d_end] # Matrix

    return (mx, Vx)
end

"""
Concatenate independent means and (co)variances of separate Gaussians in a unified mean and covariance.
Additionally returns a vector with the original dimensionalities, so statistics can later be re-separated.
"""
concatenateGaussianMV(ms::Vector{Float64}, Vs::Vector{Float64}) = (ms, Diagonal(Vs), ones(Int64, length(ms)))

# Concatenate multiple multivariate statistics
function concatenateGaussianMV(ms::Vector{Vector{Float64}}, Vs::Vector{<:AbstractMatrix})
    # Extract dimensions
    ds = [length(m_k) for m_k in ms]
    d_in_tot = sum(ds)

    # Initialize concatenated statistics
    m = zeros(d_in_tot)
    V = zeros(d_in_tot, d_in_tot)

    # Construct concatenated statistics
    d_start = 1
    for k = 1:length(ms) # For each inbound statistic
        d_end = d_start + ds[k] - 1

        m[d_start:d_end] = ms[k]
        V[d_start:d_end, d_start:d_end] = Vs[k]

        d_start = d_end + 1
    end

    return (m, V, ds) # Return concatenated mean and covariance with original dimensions (for splitting)
end

"""
Split a vector in chunks of lengths specified by ds.
"""
function split(vec::Vector{Float64}, ds::Vector{Int64})
    N = length(ds)
    res = Vector{Vector{Float64}}(undef, N)

    d_start = 1
    for k = 1:N # For each original statistic
        d_end = d_start + ds[k] - 1

        res[k] = vec[d_start:d_end]

        d_start = d_end + 1
    end

    return res
end
