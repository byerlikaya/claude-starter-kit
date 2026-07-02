---
name: devarch-module
description: |
  Backend kalıbı: MediatR CQRS handler/command/query, IResult/IDataResult sonuç sözleşmesi,
  Autofac AOP aspect zinciri, FluentValidation, Languages/i18n deseni. backend-expert bunu uygular.
  Trigger phrases: "devarch-module", "yeni handler", "command yaz", "query ekle", "validator", "aspect"
---

# Backend Kalıbı (MediatR CQRS / IResult / AOP)

> **Kit uyarlaması (lokal, .claude/):** `backend-expert` uygular. Kaynak (hizalama):
> DevArchitecture kalıbı — **adı üretilen koda / namespace / dosya / yorum / csproj / Swagger / JWT'ye
> SIZMAZ (§4.2).** Kalıp burada; üretilen artefakt projeye özgü isimlerle yazılır.

## Yerleşim
`Business/Handlers/{Entity}/` altında üç klasör: `Commands/` · `Queries/` · `ValidationRules/`.
Her istek + handler'ı **tek dosyada, nested** durur.

## Command kalıbı (yazma)
- İstek sınıfı: `IRequest<IResult>` (veya döndüreceği veri varsa `IRequest<IDataResult<T>>`).
- Handler: dış sınıfın içinde `IRequestHandler<TRequest, IResult>`; bağımlılıklar ctor'dan (repository, cache, mediator).
- Gövde: repository ile yaz → `SaveChangesAsync()` → ilgili cache anahtarını temizle → `return new SuccessResult(Messages.Added)`.

## Query kalıbı (okuma)
- İstek: `IRequest<IDataResult<IEnumerable<TDto>>>` / `IDataResult<TDto>`.
- Handler veriyi repository/DTO ile çeker → `return new SuccessDataResult<...>(data)`.

## Sonuç sözleşmesi (çıplak tip YOK)
- Başarı: `SuccessResult(mesaj)` / `SuccessDataResult<T>(data, mesaj?)`.
- Hata: `ErrorResult(mesaj)` / `ErrorDataResult<T>(mesaj)`.
- Handler asla ham `T` / `void` döndürmez; her zaman `IResult`/`IDataResult<T>`.

## AOP aspect zinciri (attribute sırası = Priority)
```
[SecuredOperation(Priority = 1)]                       // yetki
[ValidationAspect(typeof(XValidator), Priority = 2)]   // FluentValidation
[CacheAspect]            // query'de: sonucu cache'le
[CacheRemoveAspect]      // command'de: ilgili cache'i düşür
[LogAspect(typeof(FileLogger))]                        // loglama
```
- **Anonim/kimliksiz uç** (register, herkese açık webhook, health-check) → `[SecuredOperation]` **KALDIRILIR**.
- Cache anahtarları anlamlı ve tekilleştirilebilir; command sonrası ilgili anahtar temizlenir.

## Validation (FluentValidation)
`ValidationRules/` altında `AbstractValidator<TCommand>`; `RuleFor(x => x.Alan).NotEmpty()...`.
Handler'a `[ValidationAspect(typeof(TValidator))]` ile bağlanır — handler içinde manuel doğrulama yok.

## Handler'lar arası çağrı (MediatR)
Bağımlılık olarak `IMediator` alınır; tek-kayıt/iç komutlar `_mediator.Send(...)` ile çağrılır (döngüsel bağımlılık yaratmadan).

## Mesaj & i18n
Kullanıcıya dönen metinler `Messages` sabitlerinden; **yeni mesaj → proje dillerinin hepsi**
(varsayılan TR/EN/DE/RU), Languages/Translates deseni. Eksik çeviri bırakma (erteleme yok).

## İskelet örnek (projeye özgü isimlerle yaz; vendor adı yok)
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

## DoD (bu skill'in katkısı)
- `sonarqube-check` 0/0/0/0, build 0 uyarı/0 hata; `test-expert` yeşil; `/simplify` uygulanmış.
