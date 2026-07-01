package local.gitops.lab;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class UserController {
    private final HttpClient httpClient;
    private final String orderBaseUrl;
    private final String baiduUrl;

    public UserController(
            @Value("${ORDER_BASE_URL:http://order-api:8080}") String orderBaseUrl,
            @Value("${BAIDU_URL:http://www.baidu.com}") String baiduUrl) {
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(3))
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
        this.orderBaseUrl = trimTrailingSlash(orderBaseUrl);
        this.baiduUrl = baiduUrl;
    }

    @GetMapping("/")
    public Map<String, String> index() {
        return Map.of("service", "user-service", "usage", "GET /user/{id}");
    }

    @GetMapping("/version")
    public Map<String, String> version() {
        return Map.of(
                "service", "user-service",
                "version", "v1",
                "time", Instant.now().toString());
    }

    @GetMapping("/user/{userId}")
    public ResponseEntity<Map<String, Object>> user(@PathVariable String userId)
            throws IOException, InterruptedException {
        if ("1".equals(userId)) {
            return callBaidu(userId);
        }

        boolean canary = "3".equals(userId);
        return callOrder(userId, canary);
    }

    private ResponseEntity<Map<String, Object>> callBaidu(String userId)
            throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(baiduUrl))
                .timeout(Duration.ofSeconds(5))
                .GET()
                .build();
        HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        Map<String, Object> body = baseBody(userId, "baidu");
        body.put("target", baiduUrl);
        body.put("downstreamStatus", response.statusCode());
        body.put("bodyPrefix", response.body().substring(0, Math.min(120, response.body().length())));
        return ResponseEntity.status(HttpStatus.OK).body(body);
    }

    private ResponseEntity<Map<String, Object>> callOrder(String userId, boolean canary)
            throws IOException, InterruptedException {
        HttpRequest.Builder requestBuilder = HttpRequest.newBuilder(URI.create(orderBaseUrl + "/orders/" + userId))
                .timeout(Duration.ofSeconds(5))
                .GET();
        if (canary) {
            requestBuilder.header("x-order-canary", "true");
        }

        HttpResponse<String> response = httpClient.send(requestBuilder.build(), HttpResponse.BodyHandlers.ofString());

        Map<String, Object> body = baseBody(userId, canary ? "order-canary" : "order-primary");
        body.put("target", orderBaseUrl + "/orders/" + userId);
        body.put("sentHeader", canary ? "x-order-canary:true" : "none");
        body.put("downstreamStatus", response.statusCode());
        body.put("orderResponse", response.body());
        return ResponseEntity.status(HttpStatus.OK).body(body);
    }

    private Map<String, Object> baseBody(String userId, String route) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("service", "user-service");
        body.put("userId", userId);
        body.put("route", route);
        body.put("time", Instant.now().toString());
        return body;
    }

    private String trimTrailingSlash(String value) {
        if (value.endsWith("/")) {
            return value.substring(0, value.length() - 1);
        }
        return value;
    }
}

