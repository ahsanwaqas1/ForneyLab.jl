############################################
# MatrixMulitiplicationNode
############################################
# Description:
#   Multiplication with a predefined matrix:
#   out = A * in1
#   Example:
#       MatrixMulitiplicationNode([1.0]; name="my_node")
#
# Interface ids, (names) and supported message types:
#   1. (in1):
#       GaussianMessage
#       GeneralMessage
#   2. (out):
#       GaussianMessage
#       GeneralMessage
############################################

export MatrixMultiplicationNode

type MatrixMultiplicationNode <: Node
    A::Array
    name::ASCIIString
    interfaces::Array{Interface,1}
    in1::Interface
    out::Interface
    function MatrixMultiplicationNode(A::Array; args...)
        name = "#undef"
        for (key, val) in args
            if key==:name
                name=val
            end
        end
        self = new(deepcopy(A), name, Array(Interface, 2))
        # Create interfaces
        self.interfaces[1] = Interface(self)
        self.interfaces[2] = Interface(self)
        # Init named interface handles
        self.in1 = self.interfaces[1]
        self.out = self.interfaces[2]
        return self
    end
end
MatrixMultiplicationNode(; args...) = MatrixMultiplicationNode([1.0]; args...)

# Rule set for backward propagation
backward_m_rule(A::Array{Number,2}, m::Array{Number,1}) = inv(A) * m
backward_m_rule(A::Array{Number,2}, m::Array{Number,1}, W::Array{Number,2}) = pinv(A' * W * A) * A' * W * m
backward_V_rule(A::Array{Number,2}, V::Array{Number,2}) = inv(A) * V * inv(A)' # TODO: inversion only once
backward_W_rule(A::Array{Number,2}, W::Array{Number,2}) = A' * W * A
backward_xi_rule(A::Array{Number,2}, xi::Array{Number,1}) = A' * xi

# Rule set for forward propagation
forward_m_rule(A::Array{Number,2}, m::Array{Number,1}) = A * m
forward_V_rule(A::Array{Number,2}, V::Array{Number,2}) = A * V * A'
forward_W_rule(A::Array{Number,2}, W::Array{Number,2}) = inv(A)' * W * inv(A) # TODO: inversion only once
forward_xi_rule(A::Array{Number,2}, xi::Array{Number,1}) = inv(A)' * xi
forward_xi_rule(A::Array{Number,2}, xi::Array{Number,1}, V::Array{Number,2}) = pinv(A * V * A') * A * V * xi # Combination of xi and V

# Calculations for a gaussian message type; Korl (2005), table 4.1
function calculatemessage!( outbound_interface_id::Int,
                            node::MatrixMultiplicationNode,
                            inbound_messages::Array{GaussianMessage,1})
    if outbound_interface_id == 1
        # Backward message
        msg_in = inbound_messages[2]
        msg = deepcopy(msg_in)

        # Select parameterization
        # Order is from least to most computationally intensive
        if msg.xi != nothing && msg.W != nothing
            msg.m = nothing
            msg.V = nothing
            msg.W = backward_W_rule(node.A, msg.W)
            msg.xi = backward_xi_rule(node.A, msg.xi)
        elseif msg.m != nothing && msg.W != nothing
            msg.m = backward_m_rule(node.A, msg.m, msg.W) # Long version of the rule
            msg.V = nothing
            msg.W = backward_W_rule(node.A, msg.W)
            msg.xi = nothing
        elseif msg.m != nothing && msg.V != nothing && isposdef(node.A) # TODO: How to check for positive definiteness of W?
            msg.m = backward_m_rule(node.A, msg.m) # Short version of the rule, only valid if A and W are positive definite
            msg.V = backward_V_rule(node.A, msg.V)
            msg.W = nothing
            msg.xi = nothing
        else
            error("Insufficient input to calculate outbound message on interface ", outbound_interface_id, " of ", typeof(node), " ", node.name)
        end
    elseif outbound_interface_id == 2
        # Forward message
        msg_in = inbound_messages[1]
        msg = deepcopy(msg_in)

        # Select parameterization
        # Order is from least to most computationally intensive
        if msg.m != nothing && msg.V != nothing
            msg.m = forward_m_rule(node.A, msg.m)
            msg.V = forward_V_rule(node.A, msg.V)
            msg.W = nothing
            msg.xi = nothing
        elseif msg.m != nothing && msg.W != nothing
            msg.m = forward_m_rule(node.A, msg.m)
            msg.V = nothing
            msg.W = forward_W_rule(node.A, msg.W)
            msg.xi = nothing
        elseif msg.xi != nothing && msg.W != nothing && isposdef(node.A) # TODO: How to check for positive definiteness of V?
            msg.m = nothing
            msg.V = nothing
            msg.W = forward_W_rule(node.A, msg.W)
            msg.xi = forward_xi_rule(node.A, msg.xi) # Short version of the rule, only valid if A and V are positive definite
        elseif msg.xi != nothing && msg.V != nothing && msg.W != nothing
            msg.m = nothing
            msg.V = nothing
            msg.W = forward_W_rule(node.A, msg.W)
            msg.xi = forward_xi_rule(node.A, msg.xi, msg.V) # Long version of the rule
        else
            error("Insufficient input to calculate outbound message on interface ", outbound_interface_id, " of ", typeof(node), " ", node.name)
        end
    end

    # Set the outbound message
    node.interfaces[outbound_interface_id].message = msg
end

# Calculations for a general message type
function calculatemessage!( outbound_interface_id::Int,
                            node::MatrixMultiplicationNode,
                            inbound_messages::Array{GeneralMessage,1})
    if outbound_interface_id == 1
        # Backward message
        msg = GeneralMessage( pinv(node.A) * inbound_messages[2].value )
    elseif outbound_interface_id == 2
        # Forward message
        msg = GeneralMessage( node.A * inbound_messages[1].value )
    end

    # Set the outbound message
    node.interfaces[outbound_interface_id].message = msg
end