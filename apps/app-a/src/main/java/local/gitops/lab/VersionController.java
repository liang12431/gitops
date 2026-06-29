package local.gitops.lab;

import java.time.Instant;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class VersionController {
    @GetMapping("/")
    public String index() {
        return "hello from app-a";
    }

    @GetMapping("/version")
    public Map<String, String> version() {
        return Map.of(
                "app", "app-a",
                "version", "v1",
                "time", Instant.now().toString());
    }
}

