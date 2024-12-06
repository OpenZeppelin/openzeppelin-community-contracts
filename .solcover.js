module.exports = {
  skipFiles: ['mocks'],
  istanbulReporter: ['html', 'lcov', 'text-summary'],
  // Work around stack too deep for coverage
  configureYulOptimizer: true,
  solcOptimizerDetails: {
    yul: true,
    yulDetails: {
      optimizerSteps: '',
    },
  },
};
