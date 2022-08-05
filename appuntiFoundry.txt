# Tutorial Foundry

Link al book: **https://book.getfoundry.sh/**

Per inizializzare il lavoro, lancia `forge init --force`
Questo creera le seguenti cartelle 


- **lib**: la devi considerare come una sorta di node_modules, con la differenza che i pacchetti NON vengono installati attraverso `npm` ma attraverso `forge install` atttingendo da github (autore/nomeRepo).
All'interno di lib trovi anche il contratto `test.sol` che, importato, ti permette di effettuare i test.

- **src**: la devi considerare come la cartella contracts. Qui è dove sono salvati i contratti da compilare/deployare


Attraverso `forge init --force` verrà creato anche il file `.gitmodules` che può essere considerato come una sorta di package.json, in cui avverrà l'indicizzazione dei moduli utlizzati dal codice, specificando anche il loro relative path (puntando lib). Il comando crea anche un file `.gitignore`

Un altro file che viene creato è `foundry.toml` che puoi considerare come l'equivalente del file config di hardhat:
in questo file effetti il remapping cosi da importare i contratti senza problemi
un esempio è `remappings = ["@openzeppelin/=lib/openzeppelin-contracts"]` in modo tale che, ogni volta che si proverà ad accedere ai contratti di openzeppelin attraverso @openzeppelin/contracts/... sarà come accedervi attraverso lib/openzeppelin-contracts/contracts...


Dentro test.sol hai tutti gli strumenti di debugging che puoi usare. 
Se non specifichi un valore per le variabili di input, foundry proverà tutti i valori possibili di quella variabile per verificare se la logica del tuo contratto sia bucabile o meno


Puoi creare un abstract contract `Cheats.sol` in cui tenere metodi metodi che ti permettono ci cheattare (roll, warp, store etc).
Per usare questi metodi, devi crearti la variabile `Cheats internal constant cheats = Cheats(HEVM_ADDRESS)` (HEVM_ADDRESS si trova dentro test.sol)


Conviene copiare e incollare il `Makefile` e creare un `.env` file in cui salvare chiave privata, rpc endpoint etc
Questo `Makefile` definisce il contenuto di alcuni comandi (in maniera simile a quanto avviene in package.json nella sezione "script")

Per avere una fake chain in localhost puoi installare hardhat > create an empty hardhat.config.js > yarn hardhat node
Per deployare il contratto, lancia `forge create nomeContratto --private-key 0x... --rpc-url alchemy.io/...` (oppure localhost se abbiamo creato la fake chain con hardhat). Puoi anche creare uno script in `Makefile` per il deployù

Per fare i test invece è bene utilizzare `forge test -vv`. Per testare sulla mainnet (fantom) aggiungi il flag `--rpc-url https://rpc.ankr.com/fantom`