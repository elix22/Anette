package anette;

import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import haxe.io.BytesBuffer;


#if (cpp||neko)
class Server implements ISocket extends BaseHandler
{
    var serverSocket:sys.net.Socket;
    var sockets:Array<sys.net.Socket>;
    var connections:Map<sys.net.Socket, Connection> = new Map();
    public var output:BytesOutput = new BytesOutput();

    public function new(address:String, port:Int)
    {
        super();
        serverSocket = new sys.net.Socket();
        serverSocket.bind(new sys.net.Host(address), port);
        serverSocket.output.bigEndian = true;
        serverSocket.input.bigEndian = true;
        serverSocket.listen(1);
        serverSocket.setBlocking(false);
        sockets = [serverSocket];
        trace("sserver " + address + " / " + port);
    }

    public function connect(ip:String, port:Int)
    {
        throw("Anette : You can't connect as a server");
    }

    public function pump()
    {
        var inputSockets = sys.net.Socket.select(sockets, null, null, 0);
        for(socket in inputSockets.read)
        {
            if(socket == serverSocket)
            {
                trace("lel");
                var newSocket = socket.accept();
                newSocket.setBlocking(false);
                newSocket.output.bigEndian = true;
                newSocket.input.bigEndian = true;
                sockets.push(newSocket);

                var connection = new Connection(this, newSocket);
                connections.set(newSocket, connection);

                this.onConnection(connection);
            }
            else
            {
                try
                {
                    while(true)
                    {
                        var conn = connections.get(socket);
                        conn.buffer.addByte(socket.input.readByte());
                    }
                }
                catch(ex:haxe.io.Eof)
                {
                    disconnectSocket(socket, connections.get(socket));
                }
                catch(ex:haxe.io.Error)
                {
                    if(ex == haxe.io.Error.Blocked) {}
                    if(ex == haxe.io.Error.Overflow)
                        trace("OVERFLOW");
                    if(ex == haxe.io.Error.OutsideBounds)
                        trace("OUTSIDE BOUNDS");
                }
            }
        }

        // INPUT MESSAGES
        for(conn in connections)
            conn.readDatas();
    }

    @:allow(anette.Connection)
    override function disconnectSocket(connectionSocket:sys.net.Socket,
                                       connection:Connection)
    {
        // try
        // {
            connectionSocket.shutdown(true, true);
            connectionSocket.close();
        // }
        // catch(error:Dynamic)
        // {
        //     trace("Trying to shutdown socket, probably already dead");
        //     trace("Error : " + error);
        // }

        // CLEAN UP
        sockets.remove(connectionSocket);
        connections.remove(connectionSocket);
        onDisconnection(connection);
    }

    // CALLED BY CONNECTION
    @:allow(anette.Connection)
    override function send(connectionSocket:sys.net.Socket,
                                  bytes:haxe.io.Bytes,
                                  offset:Int, length:Int)
    {
        connectionSocket.output.writeBytes(bytes, offset, length);
    }

    public function flush()
    {
        // GET BROADCAST BUFFER
        var broadcastLength = this.output.length;
        var broadcastBytes = this.output.getBytes();

        for(socket in connections.keys())
        {
            var conn = connections.get(socket);

            // PUSH BROADCAST BUFFER TO EACH CONNECTION
            if(broadcastLength > 0)
                conn.output.writeBytes(broadcastBytes, 0, broadcastLength);

            conn.flush();
        }

        // RESET BROADCAST BUFFER
        this.output = new BytesOutput();
        this.output.bigEndian = true;
    }
}


#elseif (nodejs && !websocket)
import js.Node.NodeNetSocket;
import js.Node.NodeBuffer;


class Server implements ISocket extends BaseHandler
{
    var serverSocket:NodeNetSocket;
    var connections:Map<NodeNetSocket, Connection> = new Map();
    public var output:BytesOutput = new BytesOutput();

    public function new(address:String, port:Int)
    {
        super();
        var nodeNet = js.Node.require('net');
        var server = nodeNet.createServer(function(newSocket)
        {
            var connection = new Connection(this, newSocket);
            connections.set(newSocket, connection); 

            newSocket.on("data", function(buffer)
            {
                var conn = connections.get(newSocket);
                var bufferLength:Int = cast buffer.length;
                for(i in 0...bufferLength)
                    conn.buffer.addByte(buffer.readInt8(i));
            });

            this.onConnection();
            newSocket.on("error", function() {trace("error");});
            newSocket.on("close", function() {disconnectSocket(newSocket);});

        });
        server.listen(port, address);
    }

    public function connect(ip:String, port:Int)
    {
        throw("Anette : You can't connect as a server");
    }

    public function pump()
    {
        // INPUT MESSAGES
        for(conn in connections)
            conn.readDatas();
    }

    @:allow(anette.Connection)
    override function disconnectSocket(connectionSocket:NodeNetSocket)
    {
        connectionSocket.end();
        connectionSocket.destroy();

        // CLEAN UP
        connections.remove(connectionSocket);
        onDisconnection();
    }

    @:allow(anette.Connection)
    override function send(connectionSocket:NodeNetSocket,
                                  bytes:haxe.io.Bytes,
                                  offset:Int, length:Int)
    {
        connectionSocket.write(new NodeBuffer(bytes.getData()));
    }

    public function flush()
    {
        // GET BROADCAST BUFFER
        var broadcastLength = this.output.length;
        var broadcastBytes = this.output.getBytes();

        for(socket in connections.keys())
        {
            var conn = connections.get(socket);

            // PUSH BROADCAST BUFFER TO EACH CONNECTION
            if(broadcastLength > 0)
                conn.output.writeBytes(broadcastBytes, 0, broadcastLength);

            conn.flush();
        }

        // RESET BROADCAST BUFFER
        this.output = new BytesOutput();
        this.output.bigEndian = true;
    }
}

#elseif (nodejs && websocket)
import anette.Socket;


class Server implements ISocket extends BaseHandler
{
    var serverSocket:WebSocket;
    var connections:Map<WebSocket, Connection> = new Map();
    public var output:BytesOutput = new BytesOutput();

    public function new(address:String, port:Int)
    {
        super();
        var wss = new WebSocketServer({port: 32000, host:"192.168.1.4"});

        wss.on('connection', function(newSocket:WebSocket) {
            var connection = new Connection(this, newSocket);
            connections.set(newSocket, connection); 

            newSocket.on('message', function(message)
            {
                var conn = connections.get(newSocket);
                var buffer = new js.Node.NodeBuffer(message);
                var bufferLength:Int = cast buffer.length;

                // Refactor if possible
                for(i in 0...bufferLength)
                    conn.buffer.addByte(buffer.readInt8(i));
            });

            newSocket.on("close", function(o) {disconnectSocket(newSocket);});
            newSocket.on("error", function(o) {trace("error");});

            this.onConnection();
        });
    }

    public function connect(ip:String, port:Int)
    {
        throw("Anette : You can't connect as a server");
    }

    public function pump()
    {
        // INPUT MESSAGES
        for(conn in connections)
            conn.readDatas();
    }

    @:allow(anette.Connection)
    override function disconnectSocket(connectionSocket:WebSocket)
    {
        // CLEAN UP
        connections.remove(connectionSocket);
        onDisconnection();
    }

    @:allow(anette.Connection)
    override function send(connectionSocket:WebSocket,
                                  bytes:haxe.io.Bytes,
                                  offset:Int, length:Int)
    {
        connectionSocket.send(bytes.getData(), {binary: true, mask: false});
    }

    public function flush()
    {
        // GET BROADCAST BUFFER
        var broadcastLength = this.output.length;
        var broadcastBytes = this.output.getBytes();

        for(socket in connections.keys())
        {
            var conn = connections.get(socket);

            // PUSH BROADCAST BUFFER TO EACH CONNECTION
            if(broadcastLength > 0)
                conn.output.writeBytes(broadcastBytes, 0, broadcastLength);

            conn.flush();
        }

        // RESET BROADCAST BUFFER
        this.output = new BytesOutput();
        this.output.bigEndian = true;
    }
}
#end