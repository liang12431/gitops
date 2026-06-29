FROM amazoncorretto:21-alpine
WORKDIR /app
COPY target/app-b-0.1.0.jar /app/app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
