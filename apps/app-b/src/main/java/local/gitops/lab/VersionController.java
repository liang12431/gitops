package local.gitops.lab;

import java.time.Instant;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class VersionController {
    @GetMapping("/")
    public String index() {
        return "hello from app-b";
    }

    @GetMapping("/version")
    public Map<String, String> version() {
        return Map.of(
                "app", "app-b",
                "version", "v2",
                "time", Instant.now().toString());
    }
}

