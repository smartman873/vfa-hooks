# Security Policy

## Scope

This repository contains experimental DeFi contracts for volatility derivatives and cross-domain settlement automation.

## Reporting

Report vulnerabilities privately to repository maintainers with:

- impact summary
- affected files/contracts
- minimal reproduction
- suggested mitigation

## Security Controls Implemented

- callback sender verification via callback proxy allowlist
- ReactVM ID validation in callback entrypoint
- replay protection using deterministic settlement keys
- settlement idempotency per epoch
- non-reentrant state-changing external methods
- minimum size and bounds checks for settlement inputs
- anti-gaming filters for telemetry updates

## Security Review Checklist

- [ ] Hook permission bits and deployed address flags align
- [ ] `onlyPoolManager` enforcement on hook entrypoints
- [ ] Settlement path rejects unauthorized callback sender
- [ ] Replay keys cannot be reused
- [ ] Payout redistribution remains solvent
- [ ] Emergency operational controls documented and tested

## Disclaimer

No protocol is attack-proof. Use at your own risk until independently audited.
