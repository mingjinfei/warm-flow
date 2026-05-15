package com.ruoyi.framework.config;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import com.ruoyi.common.utils.StringUtils;

/**
 * Fails fast when the deployable admin starts with an unsafe JWT signing key.
 *
 * <p>The original RuoYi demo ships with a sample token secret that is fine for
 * local tutorials but dangerous when this PostgreSQL/Jimmer stack is deployed as
 * a long-running shared environment. This guard keeps production-like startup
 * safe by requiring operators to provide {@code RUOYI_TOKEN_SECRET}. Temporary
 * local experiments can explicitly set {@code RUOYI_ALLOW_INSECURE_TOKEN_SECRET=true}.
 */
@Component
public class TokenSecretStartupValidator implements ApplicationRunner
{
    private static final int MIN_SECRET_LENGTH = 32;

    private static final Set<String> INSECURE_SECRETS = new HashSet<>(Arrays.asList(
            "abcdefghijklmnopqrstuvwxyz",
            "warm-flow-jimmer-postgres-change-me",
            "warm-flow-jimmer-coldstart-change-me",
            "change-me",
            "change-me-long-random-secret"));

    @Value("${token.secret:}")
    private String tokenSecret;

    @Value("${security.allow-insecure-token-secret:false}")
    private boolean allowInsecureTokenSecret;

    @Override
    public void run(ApplicationArguments args)
    {
        if (allowInsecureTokenSecret)
        {
            return;
        }

        String secret = StringUtils.trimToEmpty(tokenSecret);
        if (StringUtils.isBlank(secret))
        {
            throw new IllegalStateException("RUOYI_TOKEN_SECRET is required. Set a strong random value of at least "
                    + MIN_SECRET_LENGTH + " characters.");
        }
        if (secret.length() < MIN_SECRET_LENGTH)
        {
            throw new IllegalStateException("RUOYI_TOKEN_SECRET is too short. Use at least "
                    + MIN_SECRET_LENGTH + " random characters.");
        }
        if (INSECURE_SECRETS.contains(secret))
        {
            throw new IllegalStateException("RUOYI_TOKEN_SECRET uses an example value. Generate and configure a "
                    + "unique strong secret before starting the service.");
        }
    }
}
