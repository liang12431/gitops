FROM amazoncorretto:21-alpine
WORKDIR /app
COPY target/gate-service.jar /app/gate-service.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/gate-service.jar"]

