//
//  Action.swift
//  RxSwift
//
//  Created by Justin Spahr-Summers on 2014-07-01.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation

/// Represents a UI action that will perform some work when executed.
///
/// Before the first execution, the action's current value will be `nil`.
/// Afterwards, it will always forward the latest results from any calls to
/// execute() on the main thread.
class Action<I, O>: Observable<Result<O>?> {
	/// The error that will be sent if execute() is invoked while the action is
	/// disabled.
	var notEnabledError: NSError {
		get {
			// TODO: Put these domains and codes into constants for the whole framework.
			// TODO: Use real userInfo here.
			return NSError(domain: "RACAction", code: 1, userInfo: nil)
		}
	}

	let _execute: I -> Promise<Result<O>>
	let _executions = ObservableProperty<Observable<Result<O>?>?>(nil)

	/// An observable of the observables returned from execute().
	///
	/// This will be non-nil while executing, nil between executions, and will
	/// only update on the main thread.
	var executions: Observable<Observable<Result<O>?>?> {
		get {
			return _executions
		}
	}

	/// Whether the action is currently executing.
	///
	/// This will only update on the main thread.
	let executing: Observable<Bool>

	/// Whether the action is enabled.
	///
	/// This will only update on the main thread.
	let enabled: Observable<Bool>

	/// Initializes an action that will be conditionally enabled, and create
	/// a Promise for each execution.
	init(enabledIf: Observable<Bool>, execute: I -> Promise<Result<O>>) {
		_execute = execute

		executing = .constant(false)
		enabled = .constant(true)

		super.init(generator: { send in
			return self.executions
				.ignoreNil(identity, initialValue: .constant(nil))
				.switchToLatest(identity)
				.observe(send)
		})

		executing = executions
			.map { $0 != nil }

		enabled = enabledIf
			.combineLatestWith(executing)
			.map { (enabled, executing) in enabled && !executing }
	}

	/// Initializes an action that will create a Promise for each execution.
	convenience init(execute: I -> Promise<Result<O>>) {
		self.init(enabledIf: .constant(true), execute: execute)
	}

	/// Executes the action on the main thread with the given input.
	///
	/// If the action is disabled when this method is invoked, the returned
	/// observable will be set to `notEnabledError`, and no result will be sent
	/// along the action itself.
	func execute(input: I) -> Observable<Result<O>?> {
		let results = ObservableProperty<Result<O>?>(nil)

		MainScheduler().schedule {
			if (!self.enabled.current) {
				results.current = Result.Error(self.notEnabledError)
				return
			}

			let promise = self._execute(input)
			self._executions.current = promise

			promise
				.start()
				.deliverOn(MainScheduler())
				.observe { maybeResult in
					if maybeResult != nil {
						// Execution completed.
						self._executions.current = nil
					}
				}
		}

		return results
	}
}
