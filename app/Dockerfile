# Imagem da API para os testes de carga (Fase 4).
# Contexto de build: a RAIZ do repositório, porque o pom.xml empacota db/migration.
#   docker compose --profile carga build app

# --- build ---------------------------------------------------------------------
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src/app

# Dependências primeiro, numa camada própria: só são baixadas de novo se o pom.xml mudar.
COPY app/mvnw app/pom.xml ./
COPY app/.mvn .mvn
RUN ./mvnw -q -B dependency:go-offline

COPY app/src src
COPY db/migration /src/db/migration
RUN ./mvnw -q -B -DskipTests package && cp target/pedidos-*.jar /src/app.jar

# --- execução ------------------------------------------------------------------
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/app.jar app.jar
EXPOSE 8080
# A JVM respeita o limite de memória do container; 75% dele vira heap máximo.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/app.jar"]
