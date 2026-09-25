# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. It builds either
# edition of FamilyPlates:
#
#   docker build -t familyplates .                            # the appliance (default)
#   docker build --build-arg EDITION=hosted -t familyplates .  # the hosted service
#
# The appliance image does not contain the saas/ engine or its gems at all.
# The hosted image is built by the hosted deployment (saas/config/deploy.yml);
# the release workflow publishes the appliance image.

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# appliance or hosted. config/boot.rb picks the bundle from FAMILYPLATES_MODE,
# so the edition an image was built as is the mode it runs in.
ARG EDITION=appliance

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    FAMILYPLATES_MODE="${EDITION}" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

LABEL org.opencontainers.image.licenses="O'Saasy"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libssl-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock Gemfile.saas Gemfile.saas.lock ./
COPY saas/familyplates-saas.gemspec ./saas/

# The same file config/boot.rb would choose, for the bundle commands that run
# before the app does.
RUN echo "export BUNDLE_GEMFILE=/rails/$([ "$FAMILYPLATES_MODE" = hosted ] && echo Gemfile.saas || echo Gemfile)" > /etc/profile.d/bundle-gemfile.sh

RUN . /etc/profile.d/bundle-gemfile.sh && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code. An appliance image drops the hosted edition, so its
# code is not merely unused but absent.
COPY . .
RUN if [ "$FAMILYPLATES_MODE" != hosted ]; then rm -rf saas Gemfile.saas Gemfile.saas.lock; fi

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN . /etc/profile.d/bundle-gemfile.sh && \
    bundle exec bootsnap precompile -j 1 app/ lib/ $([ -d saas ] && echo saas/app/ saas/lib/)

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
