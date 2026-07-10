---
name: devarch-module
description: |
  DevArchitecture backend pattern: MediatR CQRS handler/command/query, IResult/IDataResult, Autofac AOP chain,
  FluentValidation, i18n. backend-expert-csk applies it.
  Trigger phrases: "devarch-module", "new handler", "write a command", "add a query", "validator", "aspect"
---

# Backend Pattern (MediatR CQRS / IResult / AOP)

> **Kit adaptation (local, .claude/):** `backend-expert-csk` applies the `devarch-module` skill. Sources (alignment):
> the DevArchitecture pattern — **its name does NOT leak into generated code / namespace / file / comment / csproj / Swagger /
> JWT (§4.2).** The pattern lives here; the generated artifact is written with project-specific names.

## Layout
Three folders under `Business/Handlers/{Entity}/`: `Commands/` · `Queries/` · `ValidationRules/`.
Each request + its handler lives **in a single file, nested**.

## Command pattern (write)
- Request class: `IRequest<IResult>` (or `IRequest<IDataResult<T>>` if it returns data).
- Handler: `IRequestHandler<TRequest, IResult>` inside the outer class; dependencies via the ctor (repository, cache, mediator).
- Body: write via the repository → `SaveChangesAsync()` → clear the relevant cache key → `return new SuccessResult(Messages.Added)`.

## Query pattern (read)
- Request: `IRequest<IDataResult<IEnumerable<TDto>>>` / `IDataResult<TDto>`.
- The handler fetches the data via the repository/DTO → `return new SuccessDataResult<...>(data)`.

## Result contract (NO bare types)
- Success: `SuccessResult(message)` / `SuccessDataResult<T>(data, message?)`.
- Error: `ErrorResult(message)` / `ErrorDataResult<T>(message)`.
- The handler never returns a raw `T` / `void`; always `IResult`/`IDataResult<T>`.

## AOP aspect chain (attribute order = Priority)
```
[SecuredOperation(Priority = 1)]                       // authorization
[ValidationAspect(typeof(XValidator), Priority = 2)]   // FluentValidation
[CacheAspect]            // on a query: cache the result
[CacheRemoveAspect]      // on a command: drop the relevant cache
[LogAspect(typeof(FileLogger))]                        // logging
```
- **Anonymous/identity-less endpoint** (register, public webhook, health-check) → `[SecuredOperation]` is **REMOVED**.
- Cache keys are meaningful and de-duplicable; after a command the relevant key is cleared.

## Validation (FluentValidation)
`AbstractValidator<TCommand>` under `ValidationRules/`; `RuleFor(x => x.Field).NotEmpty()...`.
Bound to the handler via `[ValidationAspect(typeof(TValidator))]` — no manual validation inside the handler.

## Calls between handlers (MediatR)
`IMediator` is taken as a dependency; single-record/internal commands are called via `_mediator.Send(...)` (without creating a circular dependency).

## Messages & i18n
User-facing texts come from the `Messages` constants; **a new message → all project languages**
(default TR/EN/DE/RU), the Languages/Translates pattern. Leave no missing translation (no deferral).

## Skeleton example (write with project-specific names; no vendor name)
```csharp
public class CreateOrderCommand : IRequest<IResult>
{
    public int CustomerId { get; set; }

    public class CreateOrderCommandHandler : IRequestHandler<CreateOrderCommand, IResult>
    {
        private readonly IOrderRepository _orders;
        public CreateOrderCommandHandler(IOrderRepository orders) => _orders = orders;

        [SecuredOperation(Priority = 1)]
        [ValidationAspect(typeof(CreateOrderValidator), Priority = 2)]
        [CacheRemoveAspect]
        public async Task<IResult> Handle(CreateOrderCommand request, CancellationToken ct)
        {
            _orders.Add(new Order { CustomerId = request.CustomerId });
            await _orders.SaveChangesAsync();
            return new SuccessResult(Messages.Added);
        }
    }
}
```

## DoD (this skill's contribution)
- `sonarqube-check` 0/0/0/0, build 0 warnings/0 errors; `test-expert-csk` green; `/simplify` applied.
