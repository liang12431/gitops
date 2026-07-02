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
        return Map.of("service", "order-service", "version", "v1");
    }

    @GetMapping("/version")
    public Map<String, String> version() {
        return Map.of(
                "service", "order-service",
                "version", "v111",
                "track", "primary",
                "time", Instant.now().toString());
    }

    @GetMapping("/orders/{userId}")
    public Map<String, Object> orders(@PathVariable String userId) {
        return Map.of(
                "service", "order-service",
                "version", "v111",
                "track", "primary",
                "userId", userId,
                "orders", List.of("primary-order-" + userId + "-001", "primary-order-" + userId + "-002"),
                "time", Instant.now().toString());
    }
}

