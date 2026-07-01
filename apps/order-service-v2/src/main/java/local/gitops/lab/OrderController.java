package local.gitops.lab;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class OrderController {
    @GetMapping("/")
    public Map<String, String> index() {
        return Map.of("service", "order-service", "version", "v2");
    }

    @GetMapping("/version")
    public Map<String, String> version() {
        return Map.of(
                "service", "order-service",
                "version", "v2",
                "track", "canary",
                "time", Instant.now().toString());
    }

    @GetMapping("/orders/{userId}")
    public Map<String, Object> orders(@PathVariable String userId) {
        return Map.of(
                "service", "order-service",
                "version", "v2",
                "track", "canary",
                "userId", userId,
                "orders", List.of("canary-order-" + userId + "-A", "canary-order-" + userId + "-B"),
                "time", Instant.now().toString());
    }
}

