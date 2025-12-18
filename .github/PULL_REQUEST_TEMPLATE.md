## Description

Please include a summary of the changes and which issue is fixed (if applicable).

Fixes # (issue number)

## Type of Change

Please select the relevant option:

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] New broker support (adds parser for a new broker)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Checklist

- [ ] My code follows the style guidelines of this project
- [ ] I have performed a self-review of my code
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes (`swift test`)
- [ ] I have updated the documentation accordingly
- [ ] I have updated CHANGELOG.md (if applicable)

## New Broker Checklist (if adding a new broker)

- [ ] Created parser implementing `BrokerParser` protocol
- [ ] Added broker-specific error types
- [ ] Added comprehensive unit tests with sample data
- [ ] Updated `SupportedBroker` enum
- [ ] Updated README.md with broker information and export instructions
- [ ] Updated CHANGELOG.md

## Test Results

Please paste the output of `swift test`:

```
// Paste test output here
```

## Additional Notes

Add any additional notes for reviewers here.
