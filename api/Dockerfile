# Build from the repo root: docker build -f api/Dockerfile .
FROM dart:stable AS build

WORKDIR /app
COPY pubspec.yaml ./
COPY api/pubspec.yaml api/
COPY packages/termin_core/pubspec.yaml packages/termin_core/
# The workspace lists the Flutter app; stub it so pub resolves without Flutter.
RUN mkdir -p apps/termin && printf 'name: termin\nenvironment:\n  sdk: ^3.13.4\nresolution: workspace\n' > apps/termin/pubspec.yaml
RUN dart pub get

COPY api/ api/
COPY packages/ packages/
RUN dart build cli --target api/bin/server.dart -o output

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/output/bundle/ /app/

EXPOSE 8080
CMD ["/app/bin/server"]
