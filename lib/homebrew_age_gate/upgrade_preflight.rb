# frozen_string_literal: true

module HomebrewAgeGate
  class UpgradePreflight
    DeferredRoot = Struct.new(:package, :blocked_decisions, keyword_init: true)
    Failure = Struct.new(:stdout, :stderr, :exitstatus, :message, :write_command_output, keyword_init: true)
    Result = Struct.new(:approved_batches, :dry_run_outputs, :deferred_roots, :failure, keyword_init: true)
    IsolatedResult = Struct.new(:approved_checks, :deferred_roots, :failure, keyword_init: true)
    Selection = Struct.new(:batches, :outputs, :failure, keyword_init: true)
    Check = Struct.new(:batch, :stdout, :plan, :failure, keyword_init: true) do
      def blocked?
        plan&.skipped&.any?
      end

      def allowed?
        !failure && !blocked?
      end
    end

    def initialize(planner:, runner:, parsed_args:, color: false)
      @planner = planner
      @runner = runner
      @parsed_args = parsed_args
      @parser = DryRunParser.new
      @color = color
    end

    def filter(batches)
      approved_batches = []
      dry_run_outputs = []
      deferred_roots = []

      batches.each do |batch|
        check = preflight(batch)
        return failure_result(check.failure) if check.failure

        if check.allowed?
          approved_batches << batch
          dry_run_outputs << check.stdout
          next
        end

        return failure_result(blocked_plan_failure(check.plan)) unless deferable_blocked_plan?(check.plan)

        isolated = isolate(batch)
        return failure_result(isolated.failure) if isolated.failure

        deferred_roots.concat(isolated.deferred_roots)
        next if isolated.approved_checks.empty?

        selection = approved_after_combined_recheck(batch, isolated.approved_checks)
        return failure_result(selection.failure) if selection.failure

        approved_batches.concat(selection.batches)
        dry_run_outputs.concat(selection.outputs)
      end

      Result.new(
        approved_batches: approved_batches,
        dry_run_outputs: dry_run_outputs,
        deferred_roots: deferred_roots,
        failure: nil
      )
    end

    private

    attr_reader :planner, :runner, :parsed_args, :parser, :color

    def isolate(batch)
      approved_checks = []
      deferred_roots = []

      batch.packages.each do |package|
        root_batch = batch.with_packages([package])
        check = preflight(root_batch)
        return IsolatedResult.new(approved_checks: [], deferred_roots: [], failure: check.failure) if check.failure

        if check.allowed?
          approved_checks << check
        else
          return IsolatedResult.new(approved_checks: [], deferred_roots: [], failure: blocked_plan_failure(check.plan)) unless deferable_blocked_plan?(check.plan)

          deferred_roots << DeferredRoot.new(package: package, blocked_decisions: check.plan.skipped)
        end
      end

      IsolatedResult.new(approved_checks: approved_checks, deferred_roots: deferred_roots, failure: nil)
    end

    def approved_after_combined_recheck(original_batch, approved_checks)
      return single_root_selection(approved_checks.first) if approved_checks.length == 1

      approved_packages = approved_checks.flat_map { |check| check.batch.packages }
      combined_batch = original_batch.with_packages(approved_packages)
      combined_check = preflight(combined_batch)
      return Selection.new(batches: [], outputs: [], failure: combined_check.failure) if combined_check.failure
      return Selection.new(batches: [combined_batch], outputs: [combined_check.stdout], failure: nil) if combined_check.allowed?

      Selection.new(
        batches: approved_checks.map(&:batch),
        outputs: approved_checks.map(&:stdout),
        failure: nil
      )
    end

    def single_root_selection(check)
      Selection.new(batches: [check.batch], outputs: [check.stdout], failure: nil)
    end

    def preflight(batch)
      stdout, stderr, status = runner.capture_with_status(batch.preflight_args, env: planner.final_env)
      unless status.success?
        return Check.new(
          batch: batch,
          stdout: stdout,
          plan: nil,
          failure: Failure.new(
            stdout: stdout,
            stderr: stderr,
            exitstatus: status.exitstatus || 1,
            message: nil,
            write_command_output: true
          )
        )
      end

      planned_names = parser.parse_package_names(stdout)
      if planned_names.empty?
        return Check.new(
          batch: batch,
          stdout: stdout,
          plan: nil,
          failure: Failure.new(
            stdout: "",
            stderr: "",
            exitstatus: 1,
            message: "homebrew-age-gate: could not parse any package names from brew upgrade --dry-run output; failing closed.",
            write_command_output: false
          )
        )
      end

      plan = planner.validate_planned_names(parsed_args, planned_names, type: batch.type)
      Check.new(batch: batch, stdout: stdout, plan: plan, failure: nil)
    end

    def failure_result(failure)
      Result.new(approved_batches: [], dry_run_outputs: [], deferred_roots: [], failure: failure)
    end

    def deferable_blocked_plan?(plan)
      plan.skipped.all? { |decision| decision.reason == "too new" && decision.age_result&.known? }
    end

    def blocked_plan_failure(plan)
      Failure.new(
        stdout: "",
        stderr: blocked_plan_message(plan),
        exitstatus: 1,
        message: nil,
        write_command_output: true
      )
    end

    def blocked_plan_message(plan)
      lines = ["homebrew-age-gate: refusing to upgrade because the frozen dry-run plan includes blocked packages."]
      plan.skipped.each { |decision| lines << "  #{Report.format_decision(decision, color: color)}" }
      "#{lines.join("\n")}\n"
    end
  end
end
