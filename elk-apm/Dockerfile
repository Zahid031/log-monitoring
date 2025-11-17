# ========================
# Stage 1: Build Stage
# ========================
FROM maven:3.9.5 AS builder

# Set working directory
WORKDIR /build

# Copy pom.xml first to cache dependencies
COPY pom.xml .

# Download dependencies only
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src
#CoPY elastic-apm-agent-1.51.0.jar .
# Build the application (skip tests for faster build)
RUN mvn clean package -DskipTests

# ========================
# Stage 2: Runtime Stage
# ========================
FROM eclipse-temurin:21-jdk-jammy

# Create a non-root user and group
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Set working directory
WORKDIR /app

# Copy JAR and Elastic APM agent from builder
COPY --from=builder /build/target/*.jar app.jar
#COPY --from=builder /build/elastic-apm-agent-1.51.0.jar elastic-apm-agent.jar
COPY elastic-apm-agent-1.55.1.jar elastic-apm-agent.jar


# Change ownership to non-root user
RUN chown appuser:appgroup /app/app.jar /app/elastic-apm-agent.jar

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 8080

# JVM options for production
ENV JAVA_OPTS="-Xms256m -Xmx512m -XX:MaxMetaspaceSize=256m"
ENV APM_OPTS="-javaagent:/app/elastic-apm-agent.jar \
  -Delastic.apm.service_name=admin-api \
  -Delastic.apm.server_urls=http://192.168.169.XX:8201 \
  -Delastic.apm.secret_token=secret-key \
  -Delastic.apm.environment=dev \
  -Delastic.apm.application_packages=com.admin.service"

# Start the application with Elastic APM agent
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS $APM_OPTS -jar app.jar"]

