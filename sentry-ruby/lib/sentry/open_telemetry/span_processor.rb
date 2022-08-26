module Sentry
  module OpenTelemetry
    class SpanProcessor
      def initialize
        @otel_span_map = {}
      end

      def on_start(otel_span, _parent_context)
        return if from_sentry_sdk?(otel_span)

        scope = Sentry.get_current_scope
        parent_sentry_span = scope.get_span

        sentry_span = if parent_sentry_span
          parent_sentry_span.start_child(op: otel_span.name)
        else
          options = { name: otel_span.name, op: otel_span.name }
          transaction = Sentry::Transaction.from_sentry_trace(scope.trace, **options) if scope.trace
          scope.set_trace(nil)
          Sentry.start_transaction(transaction: transaction, **options)
        end

        scope.set_span(sentry_span)
        @otel_span_map[otel_span.context.span_id] = [sentry_span, parent_sentry_span]
      end

      def on_finish(otel_span)
        current_scope = Sentry.get_current_scope
        sentry_span, parent_span = @otel_span_map.delete(otel_span.context.span_id)
        return unless sentry_span

        sentry_span.set_op(otel_span.name)
        current_scope.set_transaction_name(otel_span.name) if sentry_span.is_a?(Sentry::Transaction)

        otel_span.attributes&.each do |key, value|
          sentry_span.set_data(key, value)
          if key == "db.statement"
            sentry_span.set_description(value)
          end
        end

        sentry_span.finish
        current_scope.set_span(parent_span) if parent_span
      end

      def force_flush(timeout: nil)
        # no-op: we rely on Sentry.close being called for the same reason as
        # whatever triggered this shutdown.
      end

      def shutdown(timeout: nil)
        # no-op: we rely on Sentry.close being called for the same reason as
        # whatever triggered this shutdown.
      end

      private

      def from_sentry_sdk?(otel_span)
        caller.any? { |line| line =~ /lib[\\\/]sentry[\\\/]background_worker.rb/ }
      end
    end
  end
end