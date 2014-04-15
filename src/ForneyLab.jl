module ForneyLab

export Message, Node, Interface, Edge
export calculatemessage, calculatemessages, calculateforwardmessage, calculatebackwardmessage

abstract Message
abstract Node

type Interface
    # An Interface belongs to a node and is used to send/receive messages.
    # An Interface has exactly one partner interface, with wich it forms an edge.
    # An Interface can be seen as a half-edge, that connects to a partner Interface to form a complete edge.
    # A message from node a to node b is stored at the Interface of node a that connects to an Interface of node b.
    node::Node
    partner::Union(Interface, Nothing)
    message::Union(Message, Nothing)
end
Interface(node::Node) = Interface(node, nothing, nothing)

type Edge
    # An Edge joins two interfaces and has a direction (from tail to head).
    # Edges are mostly useful for code readability, they are not used internally.
    # Forward messages flow in the direction of the Edge (tail to head).
    tail::Interface
    head::Interface

    function Edge(tail::Interface, head::Interface)
        if  typeof(head.message) == Nothing ||
            typeof(tail.message) == Nothing ||
            typeof(head.message) == typeof(tail.message)
            if !is(head.node, tail.node)
                tail.partner = head
                head.partner = tail
                new(tail, head)
            else
                error("Cannot connect two interfaces of the same node.")
            end
        else
            error("Head and tail message types do not match")
        end
    end
end

# Messages
include("messages.jl")

# Nodes
include("nodes/constant.jl")
include("nodes/multiplication.jl")

#############################
# Generic methods
#############################

function calculatemessage(interface::Interface, node::Node, messageType::DataType=Message)
    # Calculate the outbound message on a specific interface of a specified node.
    # The message is stored in the specified interface.
    # Optionally, messageType defines the desired type of the calculated message.

    # Sanity check
    if !is(interface.node, node)
        error("Specified interface does not belong to the specified node")
    end

    # Calculate all inbound messages
    inbound_message_types = Union() # Union of all inbound message types
    for node_interface in node.interfaces
        if is(node_interface, interface) continue end
        if node_interface.partner == nothing
            error("Cannot receive messages on disconnected interface")
        end
        if node_interface.partner.message == nothing
            # Recursive call to calculate required inbound message
            calculatemessage(node_interface.partner)
            if node_interface.partner.message == nothing
                error("Could not calculate required inbound message")
            end
            inbound_message_types = Union(inbound_message_types, typeof(node_interface.partner.message))
        end
    end

    # Collect all inbound messages
    inbound_messages = Array(inbound_message_types, length(node.interfaces))
    interface_id = 0
    for node_interface_id = 1:length(node.interfaces)
        node_interface = node.interfaces[node_interface_id]
        if is(node_interface, interface)
            interface_id = node_interface_id
            continue
        end
        inbound_messages[node_interface_id] = node.interfaces[node_interface_id].partner.message
    end

    # Calculate the actual message
    calculatemessage(interface_id, node, inbound_messages, messageType)

    # Clear all inbound messages
    for node_interface in node.interfaces
        if is(node_interface, interface) continue end
        node_interface.partner.message = nothing
    end
end
calculatemessage(interface::Interface, messageType::DataType=Message) = calculatemessage(interface, interface.node, messageType)

function calculatemessages(node::Node)
    # Calculate the outbound messages on all interfaces of node.
    for interface in node.interfaces
        calculatemessage(interface, node)
    end
end

# Calculate forward/backward messages on an Edge
calculateforwardmessage(edge::Edge) = calculatemessage(edge.tail)
calculatebackwardmessage(edge::Edge) = calculatemessage(edge.head)

end # module ForneyLab