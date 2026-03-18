module Crig
  module Client
    module ModelListingClient
      abstract def list_models : Crig::ModelList
    end

    module ModelLister(C)
      abstract def list_all : Crig::ModelList
    end
  end
end
