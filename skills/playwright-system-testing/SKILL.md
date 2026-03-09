---
name: playwright-system-testing
description: End-to-end testing for Rails with Playwright. Use when writing system tests that require reliable JavaScript execution, network interception, multi-tab scenarios, or when Capybara's Selenium/Chrome driver is flaky. Also use when the user mentions Playwright, wants fast parallel E2E tests, needs to test complex Hotwire/Turbo flows, or wants to migrate from Capybara system specs to Playwright. Covers both the capybara-playwright driver (drop-in for spec/system/) and standalone playwright-ruby-client tests.
allowed-tools: Read, Write, Edit, Bash
---

# Playwright System Testing for Rails

## Overview

Playwright is a modern end-to-end testing framework with two integration approaches for Rails:

| Approach | When to Use | Location |
|----------|-------------|----------|
| **capybara-playwright** driver | Drop-in upgrade from Capybara/Selenium; keep existing `spec/system/` tests | `spec/system/` |
| **playwright-ruby-client** standalone | Full Playwright API needed (network mocking, multi-tab, screenshots, traces) | `spec/e2e/` |

**Rule of thumb:** Start with `capybara-playwright` for existing projects. Use standalone for new projects or when you need advanced Playwright features.

---

## Approach 1: capybara-playwright (Drop-in Replacement)

### Setup

```ruby
# Gemfile
group :test do
  gem "capybara-playwright-driver"
  gem "rspec-rails"
end
```

```bash
bundle install
npx playwright install chromium  # install browser
```

```ruby
# spec/support/playwright.rb
Capybara.register_driver :playwright do |app|
  Capybara::Playwright::Driver.new(app, browser_type: :chromium, headless: true)
end

Capybara.default_driver    = :rack_test
Capybara.javascript_driver = :playwright  # replaces :selenium_chrome
```

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :playwright
  end

  config.before(:each, type: :system, js: false) do
    driven_by :rack_test
  end
end
```

### Writing Tests (same as Capybara)

```ruby
# spec/system/user_authentication_spec.rb
require "rails_helper"

RSpec.describe "User Authentication", type: :system do
  let(:user) { create(:user, email: "user@example.com", password: "SecurePass123!") }

  describe "Sign in" do
    it "signs in the user successfully" do
      visit new_user_session_path

      fill_in "Email", with: user.email
      fill_in "Password", with: "SecurePass123!"
      click_button "Sign in"

      expect(page).to have_content("Signed in successfully")
      expect(page).to have_current_path(root_path)
    end

    it "shows an error on invalid password" do
      visit new_user_session_path

      fill_in "Email", with: user.email
      fill_in "Password", with: "wrong"
      click_button "Sign in"

      expect(page).to have_content("Invalid email or password")
    end
  end
end
```

**No changes needed to existing `spec/system/` tests** — just swap the driver.

---

## Approach 2: playwright-ruby-client (Standalone)

### Setup

```ruby
# Gemfile
group :test do
  gem "playwright-ruby-client"
  gem "rspec-rails"
end
```

```bash
bundle install
npx playwright install chromium
```

```ruby
# spec/support/playwright_context.rb
module PlaywrightContext
  def self.included(base)
    base.around(:each) do |example|
      Playwright.create(playwright_cli_executable_path: "npx playwright") do |playwright|
        playwright.chromium.launch(headless: true) do |browser|
          @context = browser.new_context(base_url: Capybara.app_host || "http://localhost:#{Capybara.server_port}")
          @page = @context.new_page
          example.run
          @context.close
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include PlaywrightContext, type: :playwright
end
```

### Basic Test Structure

```ruby
# spec/e2e/user_authentication_spec.rb
require "rails_helper"

RSpec.describe "User Authentication", type: :playwright do
  let(:user) { create(:user, email: "user@example.com", password: "SecurePass123!") }

  describe "Sign in" do
    it "signs in the user successfully" do
      @page.goto("/users/sign_in")

      @page.fill('[name="user[email]"]', user.email)
      @page.fill('[name="user[password]"]', "SecurePass123!")
      @page.click("button[type='submit']")

      expect(@page.text_content(".flash-notice")).to include("Signed in successfully")
      expect(@page.url).to include("/dashboard")
    end
  end
end
```

---

## Common Patterns

### Authentication Helper

```ruby
# spec/support/playwright_auth_helpers.rb
module PlaywrightAuthHelpers
  # Sign in via UI (use sparingly — slow)
  def sign_in_via_ui(user, password: "password")
    @page.goto("/users/sign_in")
    @page.fill('[name="user[email]"]', user.email)
    @page.fill('[name="user[password]"]', password)
    @page.click("button[type='submit']")
    @page.wait_for_url("**/dashboard")
  end

  # Sign in via cookie injection (fast — preferred)
  def sign_in_as(user)
    # Use Warden test helpers or a direct session injection endpoint
    post_via_redirect sign_in_path, params: { user: { email: user.email, password: "password" } }
    # Then inject session cookie into Playwright context
    @context.add_cookies([{ name: "_session_id", value: cookies[:_session_id], domain: "localhost" }])
  end
end

RSpec.configure do |config|
  config.include PlaywrightAuthHelpers, type: :playwright
end
```

### Waiting for Turbo Navigation

```ruby
# Turbo Drive intercepts links — wait for navigation to complete
it "navigates to post detail via Turbo" do
  @page.goto("/posts")

  # Wait for Turbo navigation to complete (not just URL change)
  @page.expect_navigation(wait_until: "networkidle") do
    @page.click("a", text: "Read more")
  end

  expect(@page.title).to include("Post Detail")
end
```

### Testing Turbo Frames

```ruby
it "updates a Turbo Frame inline without full reload" do
  @page.goto("/posts/1")

  # Click edit link inside frame
  @page.click('[data-turbo-frame="edit-post"] a', text: "Edit")

  # Frame content updates — wait for form to appear
  @page.wait_for_selector("turbo-frame#edit-post form")

  @page.fill('turbo-frame#edit-post [name="post[title]"]', "Updated Title")
  @page.click('turbo-frame#edit-post button[type="submit"]')

  # Frame updates in-place
  @page.wait_for_selector("turbo-frame#edit-post", state: "visible")
  expect(@page.text_content("turbo-frame#edit-post")).to include("Updated Title")
end
```

### Testing Turbo Streams (Real-time Updates)

```ruby
it "broadcasts a new comment via Turbo Stream" do
  post = create(:post)
  sign_in_via_ui(create(:user))

  @page.goto("/posts/#{post.id}")

  # Submit a comment
  @page.fill('[name="comment[body]"]', "A new comment")
  @page.click("button", text: "Submit")

  # Turbo Stream appends the comment to the list
  @page.wait_for_selector("#comments .comment", text: "A new comment")
  expect(@page.query_selector_all("#comments .comment").count).to eq(1)
end
```

### Testing Stimulus Controllers

```ruby
it "toggles content visibility with Stimulus" do
  @page.goto("/settings")

  # Initially hidden
  expect(@page.is_visible?("[data-toggle-target='content']")).to be false

  @page.click("[data-action='toggle#toggle']")

  # Now visible
  expect(@page.is_visible?("[data-toggle-target='content']")).to be true
end
```

### Network Interception (Playwright-only, not Capybara)

```ruby
it "handles API timeout gracefully" do
  # Intercept and delay the external API call
  @page.route("**/api/external/**") do |route|
    route.fulfill(status: 504, body: '{"error": "Gateway Timeout"}')
  end

  @page.goto("/dashboard")
  expect(@page.text_content(".api-status")).to include("Service unavailable")
end

it "mocks an external payment provider" do
  @page.route("**/stripe.com/**") do |route|
    route.fulfill(
      status: 200,
      content_type: "application/json",
      body: '{"id": "ch_test_123", "status": "succeeded"}'
    )
  end

  @page.goto("/checkout")
  @page.click("button", text: "Pay now")

  @page.wait_for_selector(".success-message")
  expect(@page.text_content(".success-message")).to include("Payment successful")
end
```

### File Upload

```ruby
it "uploads a profile picture" do
  sign_in_via_ui(create(:user))

  @page.goto("/profile/edit")

  # Set input files directly (no file dialog needed)
  @page.set_input_files('input[type="file"]', Rails.root.join("spec/fixtures/files/avatar.jpg").to_s)

  @page.click("button", text: "Save")

  @page.wait_for_selector(".avatar img")
  expect(@page.get_attribute(".avatar img", "src")).to include("avatar")
end
```

### Multi-tab Testing (Playwright-only)

```ruby
it "opens a PDF preview in a new tab" do
  sign_in_via_ui(create(:user))

  new_page = @context.expect_page do
    @page.click("a[target='_blank']", text: "Preview PDF")
  end

  new_page.wait_for_load_state("networkidle")
  expect(new_page.url).to include("/reports/preview")
  new_page.close
end
```

### Screenshot on Failure

```ruby
# spec/support/playwright_screenshots.rb
RSpec.configure do |config|
  config.after(:each, type: :playwright) do |example|
    if example.exception
      screenshot_path = Rails.root.join("tmp/screenshots", "#{example.full_description.parameterize}.png")
      FileUtils.mkdir_p(screenshot_path.dirname)
      @page&.screenshot(path: screenshot_path.to_s)
      puts "Screenshot saved: #{screenshot_path}"
    end
  end
end
```

---

## Selector Strategy

Prefer selectors in this order (most to least resilient to UI changes):

```ruby
# 1. BEST: test-id attributes (explicit, not tied to styling or text)
@page.click('[data-testid="submit-order-btn"]')

# 2. GOOD: ARIA roles + text (accessible, semantic)
@page.click('button[role="button"]', text: "Submit Order")
@page.fill('[aria-label="Email address"]', "user@example.com")

# 3. OK: form field names (stable for form inputs)
@page.fill('[name="order[total]"]', "99.99")

# 4. AVOID: CSS classes (change with styling refactors)
@page.click(".btn-primary")  # ❌ brittle

# 5. NEVER: XPath (verbose, fragile)
@page.click("//button[contains(@class,'submit')]")  # ❌
```

Add `data-testid` to critical UI elements:
```erb
<%= button_to "Submit Order", orders_path, data: { testid: "submit-order-btn" } %>
```

---

## Playwright vs Capybara

| Feature | Capybara + Selenium | Playwright |
|---------|---------------------|------------|
| **Setup complexity** | Low | Medium |
| **Speed** | Moderate | Fast |
| **Flakiness** | High (known issue) | Low (auto-wait) |
| **Network mocking** | No | Yes |
| **Multi-tab** | No | Yes |
| **Trace viewer** | No | Yes |
| **Mobile emulation** | No | Yes |
| **Existing spec/system/ tests** | Works out of box | Use capybara-playwright driver |

### When to choose Playwright over Capybara

- Your Selenium-based tests are flaky (timeouts, element not found)
- You need to mock external API calls in tests
- You need multi-tab or download testing
- You want visual traces to debug failures
- New project with no existing system tests

### When to keep Capybara

- Small existing test suite — upgrade cost not worth it
- Tests are stable and passing
- No advanced scenarios needed

---

## Running Tests

```bash
# Run all playwright specs
bundle exec rspec spec/e2e/

# Run with browser visible (debug mode)
PLAYWRIGHT_HEADLESS=false bundle exec rspec spec/e2e/

# Run with trace output
PLAYWRIGHT_TRACES=true bundle exec rspec spec/e2e/

# Run specific file
bundle exec rspec spec/e2e/checkout_spec.rb

# Parallel (fast)
bundle exec parallel_tests spec/e2e/
```

---

## CI Configuration

```yaml
# .github/workflows/test.yml
- name: Install Playwright browsers
  run: npx playwright install --with-deps chromium

- name: Run E2E tests
  run: bundle exec rspec spec/e2e/
  env:
    RAILS_ENV: test
    PLAYWRIGHT_HEADLESS: "true"
```

---

## Anti-patterns to Avoid

```ruby
# ❌ Using sleep — always flaky
@page.click("button")
sleep 2
expect(@page.text_content(".result")).to include("Done")

# ✅ Wait for the element to appear
@page.click("button")
@page.wait_for_selector(".result", text: "Done")

# ❌ Asserting immediately after action (race condition)
@page.click("button[type='submit']")
expect(@page.url).to eq("/success")  # may fail before Turbo navigation completes

# ✅ Wait for navigation
@page.expect_navigation(wait_until: "networkidle") do
  @page.click("button[type='submit']")
end
expect(@page.url).to include("/success")

# ❌ Testing every unit via system tests (slow, expensive)
# Use system tests only for critical USER FLOWS, not every component

# ❌ Hardcoded waits based on timing
@page.wait_for_timeout(3000)  # ❌ flaky on slow CI

# ✅ Wait for specific condition
@page.wait_for_selector(".spinner", state: "hidden")  # waits until spinner hides
```

---

## Related Skills

| Skill | Use When |
|-------|----------|
| [`tdd-cycle`](../tdd-cycle/SKILL.md) | Full RED→GREEN→REFACTOR reference for writing E2E tests TDD-style |
| [`hotwire-patterns`](../hotwire-patterns/SKILL.md) | Understanding Turbo Frames/Streams you're testing with Playwright |
| [`viewcomponent-patterns`](../viewcomponent-patterns/SKILL.md) | Testing ViewComponent-based UI in Playwright |
| [`rails-controller`](../rails-controller/SKILL.md) | Understanding controller flows being E2E tested |

### Quick Decide

```
System testing decision:
└─> Existing Capybara tests flaky or upgrading to Playwright?
    └─> Use capybara-playwright gem — zero rewrite needed
└─> New project or new test file?
    └─> playwright-ruby-client standalone in spec/e2e/
└─> Need to mock external HTTP calls (Stripe, S3, etc.)?
    └─> Playwright-only: @page.route("**/stripe.com/**") { |r| r.fulfill(...) }
└─> Testing Turbo Frame update?
    └─> @page.wait_for_selector("turbo-frame#id", state: "visible")
└─> Testing Turbo Drive navigation?
    └─> @page.expect_navigation(wait_until: "networkidle") { @page.click("a") }
└─> Tests slow on CI?
    └─> bundle exec parallel_tests spec/e2e/ (Playwright parallelizes well)
```
