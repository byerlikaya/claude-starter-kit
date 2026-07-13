# Skeleton example (write with project-specific names; no vendor name)
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
