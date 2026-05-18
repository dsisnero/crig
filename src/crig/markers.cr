module Crig
  module Markers
    # Marker struct representing missing data in a request builder.
    struct Missing
    end

    # Marker struct representing provided data in a request builder.
    # The generic type `T` represents the type of the provided data.
    struct Provided(T)
      getter value : T

      def initialize(@value : T)
      end
    end
  end
end
