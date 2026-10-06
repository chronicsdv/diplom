# syntax=docker/dockerfile:1.7
# ^ Директива парсера: современный синтаксис (нужен для --mount=type=cache).

# =====================================================================
# VOTING — Java 17 + Spring Boot 2.5.5 + Maven, порт 8080
# 2 этапа: Maven-сборка (тяжёлый JDK) → лёгкий образ только с JRE.
# Jar разбирается на СЛОИ (layertools): зависимости почти не меняются,
# поэтому при правке кода пересобирается и пушится только маленький слой.
# =====================================================================

# Java 17 — это java.version из pom.xml. Spring Boot 2.5.x официально
# поддерживает до Java 17, поэтому 21 брать не стоит.
ARG JAVA_VERSION=17

# ---------------------------------------------------------------------
# ЭТАП 1: build — Maven + JDK, собираем jar и разбираем его на слои
# ---------------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-${JAVA_VERSION} AS build
WORKDIR /build

# Копируем только pom.xml и заранее скачиваем зависимости: этот слой кешируется,
# пока pom.xml не менялся. (Maven wrapper mvnw не используем — в репозитории нет
# папки .mvn, а Maven уже есть в образе.)
COPY pom.xml ./
# -B = batch-режим (без интерактива), -ntp = не засорять лог прогрессом загрузки.
# Кеш ~/.m2 живёт между сборками, но в образ не попадает.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -ntp dependency:go-offline

# Теперь исходники — они меняются чаще всего, поэтому идут ПОСЛЕ зависимостей
COPY src ./src
# -DskipTests — тесты гоняем отдельным шагом в CI, а не при сборке образа
# (как и написано в README сервиса).
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -ntp package -DskipTests

# Разбираем «толстый» jar на слои (Spring Boot ≥ 2.3 умеет это «из коробки»).
# Появятся папки: dependencies, spring-boot-loader, snapshot-dependencies, application.
WORKDIR /layers
RUN java -Djarmode=layertools -jar /build/target/*.jar extract

# ---------------------------------------------------------------------
# ЭТАП 2: runtime — только JRE (без Maven, компилятора и исходников)
# ---------------------------------------------------------------------
FROM eclipse-temurin:${JAVA_VERSION}-jre-alpine AS runtime

LABEL org.opencontainers.image.title="craftista-voting" \
      org.opencontainers.image.description="Craftista voting service (Spring Boot)" \
      org.opencontainers.image.source="https://github.com/craftista/craftista" \
      org.opencontainers.image.licenses="Apache-2.0"

# Непривилегированный пользователь (uid 10001), без домашней папки
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app -H app \
 # /data — папка для файла БД H2 (голоса). Compose монтирует сюда именованный том;
 # при первом запуске том наследует владельца этой папки, поэтому пользователь app сможет писать.
 && mkdir /data && chown app:app /data

WORKDIR /app

# Копируем слои от самого редко меняющегося к самому часто меняющемуся.
# Так при новой сборке Docker переиспользует тяжёлые слои с зависимостями из кеша.
COPY --from=build --chown=app:app /layers/dependencies/          ./
COPY --from=build --chown=app:app /layers/spring-boot-loader/    ./
COPY --from=build --chown=app:app /layers/snapshot-dependencies/ ./
COPY --from=build --chown=app:app /layers/application/           ./

# Настройки JVM для контейнера (JAVA_TOOL_OPTIONS JVM подхватывает автоматически):
#  -XX:MaxRAMPercentage=75   куча = до 75% лимита памяти контейнера (а не всей RAM хоста)
#  -XX:+ExitOnOutOfMemoryError  при нехватке памяти падаем сразу → оркестратор перезапустит
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

USER app

EXPOSE 8080

# Spring Actuator в проекте нет, поэтому проверяем реальный REST-эндпоинт списка
# (он возвращает 200 и [] даже при пустой БД). JVM+Spring стартуют дольше других —
# отсюда start-period 40 с.
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/api/origamis || exit 1

# Запуск из «распакованных» слоёв через загрузчик Spring Boot 2.5 (не `java -jar`).
# exec-форма → java становится PID 1 и получает SIGTERM для корректной остановки.
ENTRYPOINT ["java", "org.springframework.boot.loader.JarLauncher"]
