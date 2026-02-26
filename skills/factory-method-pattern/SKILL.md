---
name: factory-method-pattern
description: Creates objects through factory methods with Factory Method Pattern. Use for polymorphic object creation, notification systems, report generators, authentication providers, or when you need framework extensibility.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Factory Method Pattern in Rails

## Overview

The Factory Method Pattern defines an interface for creating objects, but lets subclasses decide which class to instantiate. Factory Method lets a class defer instantiation to subclasses.

**Key Insight**: Replace direct object creation with factory methods that can be overridden to produce different product types polymorphically.

## Core Components

```
Client → Creator (base) → Product (interface)
           ↓                  ↓
    Concrete Creators → Concrete Products
```

1. **Product Interface** - Declares operations all products must implement
2. **Concrete Products** - Different implementations of product interface
3. **Creator (Base)** - Declares factory method returning products
4. **Concrete Creators** - Override factory method to return specific products

## When to Use Factory Method

✅ **Use Factory Method when you need:**

- **Polymorphic object creation** - Don't know exact types beforehand
- **Framework extensibility** - Let users extend with new product types
- **Decouple creation from usage** - Client doesn't depend on concrete classes
- **Open/Closed Principle** - Add new products without modifying existing code

❌ **Don't use Factory Method for:**

- Simple object creation (use constructor)
- Creating families of related objects (use Abstract Factory)
- Complex step-by-step construction (use Builder)
- Just centralizing creation logic (use Simple Factory)

## Difference from Similar Patterns

| Aspect | Factory Method | Abstract Factory | Builder | Simple Factory |
|--------|----------------|------------------|---------|----------------|
| Purpose | Polymorphic creation | Family creation | Step-by-step | Centralized creation |
| Inheritance | Uses subclasses | Composition | Composition | Static method |
| Products | Single product type | Multiple products | Complex product | Single product |
| Extensibility | High (subclass) | High (new factory) | High (new steps) | Low (modify method) |

## Common Rails Use Cases

### 1. Notification System

```ruby
# Product interface
class Notification
  def send
    raise NotImplementedError
  end

  def recipient
    raise NotImplementedError
  end
end

# Concrete products
class EmailNotification < Notification
  def initialize(user:, message:, subject:)
    @user, @message, @subject = user, message, subject
  end

  def send
    NotificationMailer.send_notification(
      to: @user.email,
      subject: @subject,
      body: @message
    ).deliver_later
  end

  def recipient
    @user.email
  end
end

class SmsNotification < Notification
  def initialize(user:, message:)
    @user, @message = user, message
  end

  def send
    TwilioClient.send_sms(to: @user.phone, body: @message)
  end

  def recipient
    @user.phone
  end
end

# Base factory (Creator)
class NotificationFactory
  # Registry pattern with metaprogramming (Open/Closed Principle)
  FACTORIES = {
    email: 'EmailNotificationFactory',
    sms: 'SmsNotificationFactory',
    push: 'PushNotificationFactory'
  }.freeze

  # Factory method to be overridden
  def create_notification(user:, message:, **options)
    raise NotImplementedError
  end

  # Template method using factory method
  def send_notification(user:, message:, **options)
    notification = create_notification(user: user, message: message, **options)
    notification.send
  end

  # Static factory using metaprogramming instead of case statement
  def self.for(type)
    factory_class_name = FACTORIES[type]
    raise ArgumentError, "Unknown notification type: #{type}" unless factory_class_name

    Object.const_get(factory_class_name).new
  end
end

# Concrete factories
class EmailNotificationFactory < NotificationFactory
  def create_notification(user:, message:, subject: "Notification", **options)
    EmailNotification.new(user: user, message: message, subject: subject)
  end
end

class SmsNotificationFactory < NotificationFactory
  def create_notification(user:, message:, **options)
    SmsNotification.new(user: user, message: message)
  end
end

# Usage
factory = NotificationFactory.for(user.notification_preference)
factory.send_notification(user: user, message: "Hello!")
```

### 2. Report Generators (Composition Pattern)

**Note**: This example uses composition over inheritance. The Report class receives a formatter strategy through dependency injection, making it more flexible and following the Open/Closed Principle.

```ruby
# Formatter interface (Strategy pattern)
class ReportFormatter
  def format(data)
    raise NotImplementedError
  end

  def content_type
    raise NotImplementedError
  end
end

# Concrete formatters
class PdfFormatter < ReportFormatter
  def format(data)
    Prawn::Document.new do |pdf|
      pdf.text "Sales Report"
      data.each { |row| pdf.text row.to_s }
    end.render
  end

  def content_type
    'application/pdf'
  end
end

class ExcelFormatter < ReportFormatter
  def format(data)
    package = Axlsx::Package.new
    workbook = package.workbook
    workbook.add_worksheet(name: "Sales") do |sheet|
      data.each { |row| sheet.add_row row }
    end
    package.to_stream.read
  end

  def content_type
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end
end

class CsvFormatter < ReportFormatter
  def format(data)
    CSV.generate do |csv|
      data.each { |row| csv << row }
    end
  end

  def content_type
    'text/csv'
  end
end

# Report class using composition
class Report
  attr_reader :data, :formatter

  def initialize(data:, formatter:)
    @data = data
    @formatter = formatter
  end

  def generate
    formatter.format(data)
  end

  def content_type
    formatter.content_type
  end
end

# Factory creates Reports with injected formatter
class ReportFactory
  FORMATTERS = {
    pdf: PdfFormatter,
    excel: ExcelFormatter,
    csv: CsvFormatter
  }.freeze

  def create_report(data:)
    raise NotImplementedError
  end

  # Uses metaprogramming instead of case statement
  def self.for(format)
    formatter_class = FORMATTERS[format]
    raise ArgumentError, "Unknown format: #{format}" unless formatter_class

    new(formatter_class)
  end

  def initialize(formatter_class)
    @formatter_class = formatter_class
  end

  def create_report(data:)
    Report.new(data: data, formatter: @formatter_class.new)
  end
end

# Usage
factory = ReportFactory.for(params[:format])
report = factory.create_report(data: @sales_data)
send_data report.generate, type: report.content_type
```

### 3. Authentication Providers

```ruby
# Product interface
class AuthProvider
  def authenticate(credentials)
    raise NotImplementedError
  end
end

# Concrete products
class PasswordAuthProvider < AuthProvider
  def authenticate(credentials)
    user = User.find_by(email: credentials[:email])
    user&.authenticate(credentials[:password]) ? user : nil
  end
end

class OauthAuthProvider < AuthProvider
  def initialize(provider)
    @provider = provider
  end

  def authenticate(credentials)
    User.find_or_create_by_oauth(@provider, credentials[:auth_hash])
  end
end

class TokenAuthProvider < AuthProvider
  def authenticate(credentials)
    decoded = JWT.decode(credentials[:token], Rails.application.secret_key_base)
    User.find(decoded[0]['user_id'])
  rescue JWT::DecodeError
    nil
  end
end

# Factory
class AuthProviderFactory
  FACTORIES = {
    password: 'PasswordAuthProviderFactory',
    oauth: 'OauthAuthProviderFactory',
    token: 'TokenAuthProviderFactory'
  }.freeze

  def create_provider
    raise NotImplementedError
  end

  # Uses metaprogramming instead of case statement
  def self.for(type, **options)
    factory_class_name = FACTORIES[type]
    raise ArgumentError, "Unknown auth type: #{type}" unless factory_class_name

    factory_class = Object.const_get(factory_class_name)

    # Handle factories that need constructor arguments
    if type == :oauth
      factory_class.new(options[:provider])
    else
      factory_class.new
    end
  end
end

# Usage in SessionsController
factory = AuthProviderFactory.for(auth_type, provider: params[:provider])
provider = factory.create_provider

if user = provider.authenticate(credentials)
  sign_in(user)
  redirect_to dashboard_path
else
  render :new, alert: "Authentication failed"
end
```

### 4. Payment Processors

```ruby
class PaymentProcessorFactory
  FACTORIES = {
    stripe: 'StripeProcessorFactory',
    paypal: 'PaypalProcessorFactory',
    braintree: 'BraintreeProcessorFactory'
  }.freeze

  def create_processor
    raise NotImplementedError
  end

  # Uses metaprogramming instead of case statement
  def self.for(gateway)
    factory_class_name = FACTORIES[gateway]
    raise ArgumentError, "Unknown gateway: #{gateway}" unless factory_class_name

    Object.const_get(factory_class_name).new
  end
end

# Usage
factory = PaymentProcessorFactory.for(user.preferred_gateway)
processor = factory.create_processor
result = processor.process(amount: order.total, details: payment_details)
```

## Implementation Guidelines

### 1. Define Clear Product Interface

```ruby
# All products must implement common interface
class Product
  def operation
    raise NotImplementedError, "#{self.class} must implement #operation"
  end
end
```

### 2. Use Factory Method in Template Methods

```ruby
class Creator
  # Factory method
  def create_product
    raise NotImplementedError
  end

  # Template method using factory
  def execute
    product = create_product  # Factory method
    product.operation
    log_result(product)
  end

  private

  def log_result(product)
    # Common logic
  end
end
```

### 3. Use Registry Pattern with Metaprogramming (Open/Closed Principle)

**Avoid case statements** - Use a registry hash with metaprogramming to make factories extensible without modification:

```ruby
class NotificationFactory
  # Registry of available factories (can be extended via configuration)
  FACTORIES = {
    email: 'EmailNotificationFactory',
    sms: 'SmsNotificationFactory',
    push: 'PushNotificationFactory'
  }.freeze

  # Instance factory method (to be overridden)
  def create_notification(user:, message:, **options)
    raise NotImplementedError
  end

  # Static factory using metaprogramming (no case statement!)
  def self.for(type)
    factory_class_name = FACTORIES[type]
    raise ArgumentError, "Unknown type: #{type}" unless factory_class_name

    # Dynamically instantiate the factory class
    Object.const_get(factory_class_name).new
  end
end
```

**Benefits of this approach:**
- ✅ **Open/Closed Principle**: Add new types by registering in FACTORIES hash
- ✅ **No case statements**: Scales better as you add more types
- ✅ **Easy to test**: Can stub FACTORIES for testing
- ✅ **Configuration-driven**: Can load FACTORIES from config/initializers

### 4. Prefer Composition Over Inheritance

**Inheritance is for specialization and should be narrow/shallow**. For many factory scenarios, composition with dependency injection is more flexible:

```ruby
# ❌ Inheritance approach - creates many subclasses
class Report
  def generate; raise NotImplementedError; end
end

class PdfReport < Report
  def generate; # PDF logic; end
end

class ExcelReport < Report
  def generate; # Excel logic; end
end

# ✅ Composition approach - single class with injected strategy
class ReportFormatter
  def format(data); raise NotImplementedError; end
end

class PdfFormatter < ReportFormatter
  def format(data); # PDF logic; end
end

class Report
  def initialize(data:, formatter:)
    @data = data
    @formatter = formatter  # Dependency injection
  end

  def generate
    @formatter.format(@data)
  end
end

# Factory injects the appropriate formatter
class ReportFactory
  def self.for(format)
    formatter = FORMATTERS[format].new
    new(formatter)
  end

  def initialize(formatter)
    @formatter = formatter
  end

  def create_report(data:)
    Report.new(data: data, formatter: @formatter)
  end
end
```

**When to use composition:**
- Behavior varies but core structure is the same
- You want runtime flexibility (swap formatters)
- Multiple dimensions of variation (format + template + theme)

**When inheritance is OK:**
- True specialization (Car < Vehicle, Admin < User)
- Shared implementation with small variations
- Deep domain modeling where "is-a" relationship is clear

### 5. Keep Factories Simple

```ruby
# ✅ Good: Factory just creates
class EmailNotificationFactory < NotificationFactory
  def create_notification(user:, message:, **options)
    EmailNotification.new(user: user, message: message)
  end
end

# ❌ Bad: Factory has business logic
class BadEmailNotificationFactory < NotificationFactory
  def create_notification(user:, message:, **options)
    message = add_branding(message) if user.premium?  # Business logic!
    EmailNotification.new(user: user, message: message)
  end
end
```

## Testing Factory Method

```ruby
# Shared examples for product interface
RSpec.shared_examples 'a notification' do
  it 'responds to send' do
    expect(subject).to respond_to(:send)
  end

  it 'responds to recipient' do
    expect(subject).to respond_to(:recipient)
  end
end

# Test concrete product
RSpec.describe EmailNotification do
  it_behaves_like 'a notification'

  describe '#send' do
    it 'enqueues email' do
      expect { subject.send }.to have_enqueued_mail
    end
  end
end

# Test factory
RSpec.describe EmailNotificationFactory do
  describe '#create_notification' do
    it 'creates EmailNotification' do
      notification = subject.create_notification(
        user: user,
        message: "Test"
      )

      expect(notification).to be_a(EmailNotification)
    end
  end
end

# Test static factory
RSpec.describe NotificationFactory do
  describe '.for' do
    it 'returns EmailNotificationFactory for :email' do
      factory = described_class.for(:email)
      expect(factory).to be_a(EmailNotificationFactory)
    end

    it 'raises error for unknown type' do
      expect {
        described_class.for(:unknown)
      }.to raise_error(ArgumentError)
    end
  end
end
```

## Anti-Patterns to Avoid

### ❌ Don't Use Case Statements (Violates Open/Closed)

```ruby
# ❌ Bad: Case statement requires modification for new types
class NotificationFactory
  def self.for(type)
    case type
    when :email then EmailNotificationFactory.new
    when :sms then SmsNotificationFactory.new
    # Must modify this method to add new types!
    end
  end
end

# ✅ Good: Registry pattern with metaprogramming
class NotificationFactory
  FACTORIES = {
    email: 'EmailNotificationFactory',
    sms: 'SmsNotificationFactory'
    # Add new types here without modifying the method
  }.freeze

  def self.for(type)
    factory_class_name = FACTORIES[type]
    raise ArgumentError, "Unknown type: #{type}" unless factory_class_name

    Object.const_get(factory_class_name).new
  end
end
```

### ❌ Don't Put Business Logic in Factories

```ruby
# ❌ Bad
class BadFactory < NotificationFactory
  def create_notification(user:, message:, **options)
    # Business logic doesn't belong here!
    message = premium_template(message) if user.premium?
    schedule = user.timezone_adjusted_time

    EmailNotification.new(user: user, message: message, schedule: schedule)
  end
end

# ✅ Good: Factory creates, service has business logic
class GoodFactory < NotificationFactory
  def create_notification(user:, message:, **options)
    EmailNotification.new(user: user, message: message)
  end
end

class NotificationService
  def send(user:, message:)
    message = premium_template(message) if user.premium?
    factory = NotificationFactory.for(user.preference)
    notification = factory.create_notification(user: user, message: message)
    notification.send
  end
end
```

### ❌ Don't Overuse Inheritance When Composition Is Better

```ruby
# ❌ Bad: Creating many subclasses for variations
class Report
  def generate; raise NotImplementedError; end
end

class PdfReport < Report; end
class ExcelReport < Report; end
class CsvReport < Report; end
class HtmlReport < Report; end
# This creates a deep hierarchy for simple format variations

# ✅ Good: Use composition with strategy pattern
class Report
  def initialize(data:, formatter:)
    @data = data
    @formatter = formatter  # Injected dependency
  end

  def generate
    @formatter.format(@data)
  end
end

# Single Report class + multiple formatters (more flexible)
```

**Remember**: Inheritance is for specialization and should be narrow/shallow. Use composition when you're varying behavior rather than specializing types.

### ❌ Don't Skip Product Interface

```ruby
# ❌ Bad: No common interface
class EmailNotification
  def send_email; end
end

class SmsNotification
  def send_sms; end  # Different method name!
end

# ✅ Good: Common interface
class Notification
  def send
    raise NotImplementedError
  end
end

class EmailNotification < Notification
  def send
    # Email logic
  end
end
```

### ❌ Don't Create God Factories

```ruby
# ❌ Bad: Factory creates unrelated products
class GodFactory
  def create_user; end
  def create_post; end
  def create_notification; end
  def create_payment; end
end

# ✅ Good: Separate factories for each product family
class UserFactory; end
class NotificationFactory; end
class PaymentFactory; end
```

## Decision Tree

### When to use Factory Method vs alternatives:

**Creating a single object with known type?**
→ YES: Use constructor
→ NO: Keep reading

**Need step-by-step construction with many options?**
→ YES: Use Builder Pattern
→ NO: Keep reading

**Creating families of related objects?**
→ YES: Use Abstract Factory
→ NO: Keep reading

**Just centralizing simple creation logic?**
→ YES: Use Simple Factory (static method)
→ NO: Keep reading

**Need polymorphic creation with subclass extensibility?**
→ YES: Use Factory Method Pattern ✅

## Benefits

✅ **Decoupling** - Client doesn't depend on concrete classes
✅ **Extensibility** - Add new products without modifying existing code
✅ **Polymorphism** - Create objects without knowing exact types
✅ **Single Responsibility** - Creation logic separated from usage
✅ **Open/Closed** - Open for extension, closed for modification

## Drawbacks

❌ **More classes** - Requires factory hierarchy
❌ **Indirection** - Extra layer between client and product
❌ **Overkill** - Too complex for simple creation needs

## Real-World Rails Examples

### File Parsers

```ruby
class ParserFactory
  FACTORIES = {
    csv: 'CsvParserFactory',
    json: 'JsonParserFactory',
    xml: 'XmlParserFactory'
  }.freeze

  def self.for(format)
    factory_class_name = FACTORIES[format]
    raise ArgumentError, "Unknown format: #{format}" unless factory_class_name

    Object.const_get(factory_class_name).new
  end
end

factory = ParserFactory.for(file.format)
parser = factory.create_parser
data = parser.parse(file.content)
```

### Shipping Calculators

```ruby
class ShippingCalculatorFactory
  FACTORIES = {
    ups: 'UpsCalculatorFactory',
    fedex: 'FedexCalculatorFactory',
    usps: 'UspsCalculatorFactory'
  }.freeze

  def self.for(carrier)
    factory_class_name = FACTORIES[carrier]
    raise ArgumentError, "Unknown carrier: #{carrier}" unless factory_class_name

    Object.const_get(factory_class_name).new
  end
end

factory = ShippingCalculatorFactory.for(order.shipping_carrier)
calculator = factory.create_calculator
cost = calculator.calculate(order.weight, order.destination)
```

### Search Engines

```ruby
class SearchEngineFactory
  FACTORIES = {
    elasticsearch: 'ElasticsearchFactory',
    postgres: 'PostgresSearchFactory',
    algolia: 'AlgoliaFactory'
  }.freeze

  def self.for(engine)
    factory_class_name = FACTORIES[engine]
    raise ArgumentError, "Unknown engine: #{engine}" unless factory_class_name

    Object.const_get(factory_class_name).new
  end
end

factory = SearchEngineFactory.for(Rails.configuration.search_engine)
search = factory.create_search
results = search.query(params[:q])
```

## Summary

**Use Factory Method when:**
- You don't know exact types beforehand
- You want framework extensibility
- You need polymorphic object creation
- Client shouldn't depend on concrete classes

**Avoid Factory Method when:**
- Simple object creation (use constructor)
- Creating families (use Abstract Factory)
- Complex construction (use Builder)
- Just centralizing (use Simple Factory)

**Most common Rails use cases:**
1. Notification systems (Email, SMS, Push, Slack)
2. Report generators (PDF, Excel, CSV, HTML)
3. Authentication providers (Password, OAuth, Token, SSO)
4. Payment processors (Stripe, PayPal, Braintree)
5. File parsers (CSV, JSON, XML, YAML)
6. Search engines (Elasticsearch, PostgreSQL, Algolia)
7. Shipping calculators (UPS, FedEx, USPS, DHL)
8. Logging adapters (File, Database, External service)

**Key Pattern:**
```ruby
# 1. Product interface
class Product
  def operation; raise NotImplementedError; end
end

# 2. Concrete products
class ConcreteProductA < Product
  def operation; end
end

# 3. Base factory
class Factory
  def create_product; raise NotImplementedError; end
  def self.for(type); end  # Static factory
end

# 4. Concrete factory
class ConcreteFactoryA < Factory
  def create_product
    ConcreteProductA.new
  end
end

# 5. Usage
factory = Factory.for(:a)
product = factory.create_product
product.operation
```
