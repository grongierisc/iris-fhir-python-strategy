import iris

class Utils:

    def update_capability_statement(self, endpoint):
        strategy = iris.cls('HS.FHIRServer.API.InteractionsStrategy').GetStrategyForEndpoint(endpoint)
        interactions = strategy.NewInteractionsInstance()
        interactions.SetMetadata( strategy.GetMetadataResource() )