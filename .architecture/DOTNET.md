# DOTNET.md

This repository follows a **strict .NET Clean Architecture pattern**.  
All AI agents, contributors, and automated tools must adhere to these architectural rules when modifying or generating code.

The architecture is optimized for:

- ASP.NET Core
- MediatR
- EF Core
- FluentValidation
- Dependency Injection
- Feature-based organization

The goal is to keep the system:

- Highly testable
- Framework isolated
- Business‑logic centric
- Maintainable at enterprise scale

---

# Core Architecture Rule

**Dependencies must always point inward.**

```
Presentation -> Application -> Domain
Infrastructure -> Application / Domain
```

Never:

```
Domain -> Application
Domain -> Infrastructure
Application -> Infrastructure implementations
Application -> Presentation
```

---

# Project Structure

Standard project layout:

```
src/
  MyApp.Domain/
  MyApp.Application/
  MyApp.Infrastructure/
  MyApp.Presentation/

tests/
  MyApp.Domain.Tests/
  MyApp.Application.Tests/
  MyApp.Infrastructure.Tests/
  MyApp.Presentation.Tests/
```

---

# Domain Layer

Project: `MyApp.Domain`

Contains only **pure business logic**.

Allowed:

- Entities
- Value Objects
- Domain Events
- Domain Services
- Enums
- Interfaces only if they represent domain concepts

Domain must be **framework independent**.

Never reference:

- ASP.NET Core
- EF Core
- MediatR
- Azure SDK
- Logging frameworks
- HTTP libraries

Entities must enforce **business invariants**.

Example:

```csharp
public class Order
{
    public Guid Id { get; private set; }
    public Money Total { get; private set; }

    public void AddItem(Product product)
    {
        if(product == null)
            throw new DomainException("Product cannot be null");

        Total += product.Price;
    }
}
```

Rules:

- Entities control their invariants
- Value objects should be immutable
- Avoid primitive obsession
- No persistence annotations

---

# Application Layer

Project: `MyApp.Application`

Contains **use cases and orchestration logic**.

Key responsibilities:

- Commands
- Queries
- Handlers
- Validators
- Interfaces for external services
- DTOs used between layers

Uses:

- **MediatR**
- **FluentValidation**

Folder layout:

```
Application/
  Orders/
    Commands/
      CreateOrder/
        CreateOrderCommand.cs
        CreateOrderHandler.cs
        CreateOrderValidator.cs
    Queries/
      GetOrder/
        GetOrderQuery.cs
        GetOrderHandler.cs
```

Command example:

```csharp
public record CreateOrderCommand(Guid CustomerId) : IRequest<Guid>;
```

Handler example:

```csharp
public class CreateOrderHandler : IRequestHandler<CreateOrderCommand, Guid>
{
    private readonly IOrderRepository _repository;

    public CreateOrderHandler(IOrderRepository repository)
    {
        _repository = repository;
    }

    public async Task<Guid> Handle(CreateOrderCommand request, CancellationToken cancellationToken)
    {
        var order = new Order(request.CustomerId);

        await _repository.AddAsync(order);

        return order.Id;
    }
}
```

Rules:

- No EF Core usage
- No HTTP access
- No direct infrastructure SDK usage
- All external dependencies defined via interfaces

Example abstraction:

```csharp
public interface IEmailSender
{
    Task SendAsync(string email, string subject, string body);
}
```

---

# Infrastructure Layer

Project: `MyApp.Infrastructure`

Contains **implementation details**.

Responsibilities:

- EF Core DbContext
- Repository implementations
- External API clients
- Email services
- File storage
- Caching
- Message bus implementations

Example repository:

```csharp
public class OrderRepository : IOrderRepository
{
    private readonly AppDbContext _context;

    public OrderRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task AddAsync(Order order)
    {
        await _context.Orders.AddAsync(order);
        await _context.SaveChangesAsync();
    }
}
```

Rules:

- Infrastructure can reference Application + Domain
- Infrastructure must not contain business rules
- All framework code belongs here

---

# Presentation Layer

Project: `MyApp.Presentation`

Typically an **ASP.NET Core Web API**.

Responsibilities:

- Controllers
- Endpoint definitions
- Authentication
- Model binding
- HTTP response mapping

Controllers must be **thin**.

Example:

```csharp
[ApiController]
[Route("orders")]
public class OrdersController : ControllerBase
{
    private readonly IMediator _mediator;

    public OrdersController(IMediator mediator)
    {
        _mediator = mediator;
    }

    [HttpPost]
    public async Task<IActionResult> Create(CreateOrderCommand command)
    {
        var id = await _mediator.Send(command);

        return Ok(id);
    }
}
```

Rules:

- No business logic
- No EF Core usage
- No domain orchestration
- Only call MediatR

---

# Validation

Validation must use **FluentValidation**.

Example:

```csharp
public class CreateOrderValidator : AbstractValidator<CreateOrderCommand>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.CustomerId)
            .NotEmpty();
    }
}
```

Validation occurs in:

Application pipeline via MediatR behavior.

---

# MediatR Pipeline Behaviors

Application must support behaviors for:

- Validation
- Logging
- Transactions

Example:

```
ValidationBehavior
LoggingBehavior
TransactionBehavior
```

Rules:

- Behaviors live in Application
- Infrastructure wiring happens in Presentation startup

---

# EF Core Rules

EF Core belongs **only in Infrastructure**.

Guidelines:

- Use separate persistence models if domain purity requires it
- Keep migrations in Infrastructure
- Avoid leaking DbContext outside infrastructure

Never:

- Inject DbContext into handlers
- Inject DbContext into controllers

---

# DTO Rules

DTO placement:

| DTO Type | Location |
|--------|--------|
| API Request | Presentation |
| API Response | Presentation |
| Application contract | Application |
| Domain model | Domain |

Never reuse domain entities directly as API models.

---

# Mapping

Mapping must happen at boundaries.

Recommended tools:

- Mapster
- Manual mapping
- AutoMapper (allowed but discouraged if excessive)

Boundaries:

```
HTTP -> Command
Persistence -> Domain
Domain -> Response DTO
```

---

# Dependency Injection

All DI configuration occurs in:

```
Presentation startup
or
Infrastructure extension methods
```

Example:

```csharp
services.AddApplication();
services.AddInfrastructure();
```

Infrastructure registers concrete services.

---

# Testing Strategy

Domain tests:

- pure unit tests
- no mocks required

Application tests:

- use mocks for repositories

Infrastructure tests:

- integration tests
- test database

Presentation tests:

- endpoint tests
- serialization tests

---

# Naming Conventions

Good:

```
CreateOrderCommand
GetOrdersQuery
OrderRepository
Money
EmailAddress
```

Avoid:

```
Helper
Manager
Processor
Util
CommonService
```

---

# Anti‑Patterns

Never introduce:

- Fat Controllers
- Business logic in Infrastructure
- DbContext usage in Application
- Static service locators
- Domain models coupled to EF

---

# Code Generation Rules for Agents

When generating code:

1. Start with Domain.
2. Create Application command/query.
3. Define interfaces in Application.
4. Implement them in Infrastructure.
5. Expose via Presentation controller.

Never skip layers.

---

# Summary

Architecture priorities:

1. Domain purity
2. Application use‑case clarity
3. Infrastructure isolation
4. Thin presentation layer
5. High testability

When in doubt:

**Move logic inward toward the Domain.**