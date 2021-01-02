def gemfile
  @gemfile ||= File.read('Gemfile')
end

def gem(*args)
  options = args.extract_options!
  name, *versions = args

  if gemfile.match?(/gem ['"]#{name}/)
    log :template, "#{name} is already installed"
    return
  end

  super
end

gem 'devise'
gem 'inline_svg'
gem 'pagy'
gem 'pundit'
gem 'sidekiq'
gem 'simple_form'

gem_group :development do
  gem 'annotate'
  gem 'rubocop'
  gem 'rubocop-rails'
end

gem_group :development, :test do
  gem 'dotenv-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'i18n-tasks'
  gem 'letter_opener'
  gem 'rspec-rails'
  gem 'webmock'
end

gem_group :test do
  gem 'capybara'
  gem 'capybara-screenshot'
  gem 'rspec-log_matcher'
  gem 'rspec-retry'
  gem 'shoulda-matchers'
  gem 'simplecov', '~> 0.17.1', require: false
  gem 'webdrivers'
end

# Remove comments frm Gemfile
gemfile_contents = File.read('Gemfile')
File.open('Gemfile', 'w') do |f|
  f.puts gemfile_contents.split("\n").select { |l| l.strip[0] != '#' }
end

# TODO: Remove empty group blocks from Gemfile. Useful for app:template re-runs.

application "config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'debug').to_sym"
environment("config.hosts << ENV.fetch('LOCAL_TUNNEL_HOST', '')", env: 'development')
environment("config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: 'development')
environment(<<~RUBY, env: 'production')
  config.action_mailer.default_url_options = { host: ENV.fetch('HOST_NAME') }
  config.action_mailer.smtp_settings = {
    address: ENV.fetch('SMTP_SERVER'),
    authentication: ENV.fetch('SMTP_AUTHENTICATION'),
    domain: ENV.fetch('HOST_NAME'),
    enable_starttls_auto: ENV.fetch('SMTP_ENABLE_STARTTLS_AUTO') == 'true',
    password: ENV.fetch('SMTP_PASSWORD'),
    port: ENV.fetch('SMTP_PORT'),
    user_name: ENV.fetch('SMTP_LOGIN')
  }
  config.action_mailer.delivery_method = :smtp
RUBY

file '.github/workflows/ci.yml', <<~YAML
  name: CI

  on:
    pull_request:
      branches:
        - 'master'
    push:
      branches:
        - 'master'

  jobs:
    build:
      if: "! contains(toJSON(github.event.commits.*.message), '[skip-ci]')"
      runs-on: ubuntu-latest

      env:
        PGHOST: localhost
        PGUSER: postgres
        RAILS_ENV: test
        AWS_ACCESS_KEY_ID:
        AWS_SECRET_ACCESS_KEY:
        AWS_REGION:
        AWS_BUCKET:

      services:
        postgres:
          image: postgres:11.5
          env:
            POSTGRES_USER: postgres
            POSTGRES_DB: postgres
          ports: ["5432:5432"]
          options: --heath-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5

      steps:
      - uses: actions/checkout@v2
      - name: Setup Ruby
        uses: actions/setup-ruby@v1
        with:
          ruby-version: 3.0.x

      - name: Install PostgreSQL 11 client
        run: |
          sudo apt-get -yqq install libpq-dev
      - uses: actions/cache@v2
        with:
          path: vendor/bundle
          key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
          restore-keys: |
            ${{ runner.os }}-gems-
      - name: Get yarn cache directory path
        id: yarn-cache-dir-path
        run: echo "::set-output name=dir::$(yarn cache dir)"
      - uses: actions/cache@v2
        id: yarn-cache
        with:
          path: ${{ steps.yarn-cache-dir-path.outputs.dir }}
          key: ${{ runner.os }}-yarn-${{ hashFiles('**/yarn.lock') }}
          restore-keys: |
            ${{ runner.os }}-yarn-
      - name: Build App
        run: |
          bundle config path vendor/bundle
          gem install bundler
          bundle install --jobs 4 --retry 3
          bin/rails db:setup
          bin/rails assets:precompile
      - name: Rubocop
        run: bundle exec rubocop

      - name: I18n Health
        run: bundle exec i18n-tasks health

      - name: Tests
        run: bundle exec rspec
YAML

file '.env.dist', <<~TXT
  AWS_ACCESS_KEY_ID=
  AWS_BUCKET=
  AWS_REGION=
  AWS_SECRET_ACCESS_KEY=
  HOST_NAME=
  LOCAL_TUNNEL_HOST=
  RAILS_LOG_LEVEL=
  SMTP_AUTHENTICATION=
  SMTP_ENABLE_STARTTLS_AUTO=
  SMTP_LOGIN=
  SMTP_PASSWORD=
  SMTP_PORT=
  SMTP_SERVER=
TXT

run 'bundle install'
run 'spring stop'
run 'bundle exec rails generate rspec:install'
run 'bundle exec rails generate simple_form:install'
run 'bundle exec rails generate devise:install'
run 'bundle exec rails generate pundit:install'
run 'cp $(i18n-tasks gem-path)/templates/config/i18n-tasks.yml config/'
run 'bundle exec rails db:create db:migrate'

prepend_to_file 'spec/rails_helper.rb' do <<~RUBY
  require 'simplecov'
  SimpleCov.start 'rails' do
    add_group 'Forms', 'app/forms'
    add_group 'Presenters', 'app/presenters'
    add_group 'Queries', 'app/queries'
  end\n
RUBY
end
append_to_file 'spec/rails_helper.rb' do <<~RUBY
  \nShoulda::Matchers.configure do |config|
    config.integrate do |with|
      with.test_framework :rspec
      with.library :rails
    end
  end

  Capybara.configure do |config|
    config.javascript_driver = :selenium_chrome_headless
  end
RUBY
end

after_bundle do
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit' }
end
