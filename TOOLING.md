# Difference with @openzeppelin/contracts

## Slither

Community repo uses a different slither config than @openzeppelin/contracts. 
We had to remove the following line that causes issues:

```json
"compile_force_framework": "hardhat"
```

