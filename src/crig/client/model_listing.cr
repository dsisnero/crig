module Crig
  module Client
    module ModelListingClient
      abstract def list_models : Crig::ModelList

      def list_models_async : Channel(Crig::Concurrency::Result(Crig::ModelList))
        Crig::Concurrency.run do
          list_models
        end
      end
    end

    module ModelLister(C)
      abstract def initialize(client : C)
      abstract def list_all : Crig::ModelList

      def list_all_async : Channel(Crig::Concurrency::Result(Crig::ModelList))
        Crig::Concurrency.run do
          list_all
        end
      end
    end
  end
end
