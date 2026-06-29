import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class GateService {
    private static final Set<String> OPEN_GATES = ConcurrentHashMap.newKeySet();

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", 8080), 0);
        server.createContext("/", GateService::handle);
        server.start();
        System.out.println("gate-service started on :8080");
    }

    private static void handle(HttpExchange exchange) throws IOException {
        String path = exchange.getRequestURI().getPath();
        String method = exchange.getRequestMethod();
        String gate = gateName(path);

        if (gate == null) {
            respond(exchange, 200, "gate-service");
            return;
        }

        if (("PUT".equals(method) || "POST".equals(method)) && path.endsWith("/open")) {
            OPEN_GATES.add(gate);
            respond(exchange, 200, "opened " + gate);
            return;
        }

        if ("POST".equals(method) && path.endsWith("/check")) {
            if (OPEN_GATES.remove(gate)) {
                respond(exchange, 200, "allowed " + gate);
            } else {
                respond(exchange, 403, "closed " + gate);
            }
            return;
        }

        if ("GET".equals(method) && path.endsWith("/check")) {
            respond(exchange, OPEN_GATES.contains(gate) ? 200 : 404, OPEN_GATES.contains(gate) ? "open" : "closed");
            return;
        }

        respond(exchange, 404, "not found");
    }

    private static String gateName(String path) {
        if (path.startsWith("/gate/promotion")) {
            return "promotion";
        }
        if (path.startsWith("/gate/rollback")) {
            return "rollback";
        }
        return null;
    }

    private static void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
        exchange.close();
    }
}
