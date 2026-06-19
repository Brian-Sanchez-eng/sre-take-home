# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
ARG VERSION=0.0.0
WORKDIR /src

# Restore against project files only so this layer caches across source changes.
COPY global.json SreTakeHome.sln ./
COPY src/CandidateApi/CandidateApi.csproj src/CandidateApi/
COPY src/CandidateApi.Contracts/CandidateApi.Contracts.csproj src/CandidateApi.Contracts/
COPY tests/CandidateApi.Tests/CandidateApi.Tests.csproj tests/CandidateApi.Tests/
RUN dotnet restore src/CandidateApi/CandidateApi.csproj

COPY . .
RUN dotnet publish src/CandidateApi/CandidateApi.csproj \
    -c "$BUILD_CONFIGURATION" \
    -p:Version="$VERSION" \
    --no-restore \
    -o /app/publish

# Chiseled runtime: no shell/package manager, runs as non-root (UID 64198).
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled AS final
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0

COPY --from=build /app/publish .

ARG VERSION=0.0.0
ARG REVISION=unknown
LABEL org.opencontainers.image.title="candidate-api" \
      org.opencontainers.image.source="https://github.com/CoterieInsure/sre-take-home" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}"

USER 64198
ENTRYPOINT ["dotnet", "CandidateApi.dll"]
