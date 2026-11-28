# pipeline-Claude

Um comando do Claude Code, `/pipeline "<feature>"`, que transforma uma descrição de feature em código implementado, testado e verificado. No caminho principal são dois agentes. Um implementa escrevendo os testes antes do código. O outro, com contexto limpo, não escreveu nada e tenta quebrar o resultado. O Planner e o E2E só entram quando o pedido ou a mudança pedem. Entre os estágios há gates, e o pipeline nunca faz commit, push ou merge sem você responder "s".

```
/pipeline "rate limiting em POST /auth/login: 5 tentativas/min por IP; na 6ª, 429 com {error: 'rate_limited'}"

  Triagem ──► [Planner] ──► Builder ──► [E2E] ──► Verifier ──► Committer ──► [PR]
  o pedido     só se o       testes,     só com    ataca e      commits      com "s"
  está         pedido        código,     tela      julga        gitflow
  completo?    não passar    checks                             (Haiku)
                               ▲                       │
                               └───── fix (até 2) ◄────┘
```

Medido num A/B controlado no projeto flash-sales. A mesma feature (F02, Idempotency-Key) foi feita duas vezes a partir do mesmo commit, uma pelo pipeline e outra por um agente direto, com o mesmo oráculo oculto e uma revisão cega:

| | agente direto | pipeline | diferença |
|---|---:|---:|---:|
| defeitos alto/médio na entrega | 1 | 0 | −100% |
| retrabalho depois da entrega | 27 linhas, 1 rodada | 0 | −100% |
| tokens até o aceite | 201k | 204k | +1% |
| tempo até o aceite | 9,5 min | 17,9 min | +88% |

É uma feature só, então os percentuais valem com os números absolutos ao lado. O pipeline custa praticamente os mesmos tokens que o agente direto, entrega sem o retrabalho e gasta quase o dobro do tempo. A versão anterior, com oito agentes, gastava seis vezes mais tokens; a história está em [De oito agentes para dois](#de-oito-agentes-para-dois).

## Por que existe

Um agente de IA sem processo produz código que parece pronto. O custo aparece depois, em correções, retrabalho e PRs que voltam. A causa quase sempre é uma destas duas: a entrada era ambígua, ou ninguém verificou a saída de forma independente.

O pipeline ataca as duas pontas com o mínimo de etapas:
- **Entrada ambígua.** A triagem barra o pedido ambíguo e só nesse caso chama o Planner.
- **Saída sem verificação.** Um Verifier que não escreveu o código tenta quebrá-lo antes do commit, contra o sistema rodando.

Nas medições, foi essa verificação independente que fez diferença na qualidade. As outras etapas da versão antiga só custavam tokens e tempo.

## Como funciona

Os agentes se comunicam apenas por arquivos na pasta `.pipeline/` do projeto. No fim do run tudo é arquivado em `.pipeline/history/`, com uma linha no `LOG.md`, então o histórico de cada feature sobrevive.

### Triagem (sem agente)

O próprio orquestrador responde seis perguntas sobre o pedido:
1. A interface está explícita (rotas, entradas, saídas, erros)?
2. As regras são testáveis (números e mensagens exatas, não adjetivos)?
3. O escopo está delimitado?
4. Não há decisão em aberto?
5. A mudança é reversível e local (sem migrar dados existentes nem mudar o contrato de outro serviço)?
6. São até cerca de 500 linhas?

Se tudo for "sim", o pedido vira o spec e o run vai direto para o Builder. Se o pedido for grande, o pipeline sugere dividir em partes menores.

### Planner (só quando a triagem falha)

Lê o pedido, explora o repositório e escreve `.pipeline/spec.md` em no máximo 80 linhas: critérios de aceite numerados e falsificáveis, casos de borda, segurança e o que fica fora do escopo. Não escreve código. Quando o pedido deixa uma decisão em aberto, ele a registra como pergunta e o pipeline para. Você responde, ele grava a resposta em `## Decisions` e o run continua.

### Builder

Implementa a feature com os testes primeiro, num contexto só:
1. Transforma o spec numa lista de critérios.
2. Escreve um teste por critério, com os valores esperados copiados do spec.
3. Roda os testes antes de existir código, e eles têm que falhar. Esse é o red check.
4. Implementa o mínimo que faz os testes passarem, sem mexer nos testes.
5. Roda typecheck, lint, a suíte completa e o build.
6. Roda os testes novos três vezes seguidas para pegar instabilidade.

Ele também valida a entrada do cliente na fronteira, para que entrada nenhuma vire 500. Por fim deixa em `.pipeline/build.md` a tabela de critério por teste, os checks e um mapa curto do que mudou e de como subir o app.

### E2E Tester (só quando a mudança tem tela)

Testa a tela no sistema rodando: Playwright para web, Maestro para app React Native (no iPhone ou no simulador). Antes de qualquer comando, exige que o alvo seja local ou de teste. A API de backend não passa por aqui, porque o Verifier já a ataca rodando.

### Verifier

Não escreveu o código e não o conserta. Com contexto limpo, escolhe até três ataques a partir do spec e da interface:
- **Entrada hostil:** vazio, enorme, tipo errado, caracteres de controle, Unicode malformado.
- **Concorrência e repetição:** a mesma chamada N vezes ao mesmo tempo, duas instâncias.
- **Dependência falhando:** banco travado, timeout.
- **Autorização:** o recurso de outro usuário.

Os ataques rodam contra a API de verdade. Um ataque que passa é apagado; um que falha vira teste `*.breaker.*` e entra no relatório. Depois o Verifier confere se cada critério tem um teste real, roda a suíte completa e lê o diff procurando erros de correção, sem comentar estilo. O veredito é SHIP, NEEDS WORK ou BLOCK, em `.pipeline/verify.md`.

### Committer

Só roda depois de um SHIP e de você responder "s", em Haiku, porque o trabalho é mecânico. Ele:
- divide o trabalho em commits pequenos por camada, no padrão Conventional Commits;
- na conta compartilhada AtomStudioFerramentas, prefixa cada commit com `[Nome]`;
- procura segredos antes de cada commit e nunca commita o que já estava alterado antes do run;
- termina cada commit com `Journify: <id da task>`, que é como a pipeline sabe quais tasks já estão na branch;
- avalia se é hora de abrir o PR.

### PR Creator

Com outro "s", dá push e abre o PR com os links de todas as tasks do Journify da branch, a soma dos pontos e um plano de testes por critério, que o robô de testes executa.

### Limites de PR

- **Até 8 pontos por PR.** No Setup, a pipeline soma os pontos das tasks que já estão na branch com os da task nova. Se passar de 8, ela para e pede uma branch nova. Uma task sozinha acima de 8 precisa ser dividida no Journify antes.
- **Até 2 PRs abertos por pessoa em cada projeto.** Com 2 abertos naquele repo, a branch nova pode ser trabalhada, mas só vira PR depois que um deles for aprovado. Na conta compartilhada AtomStudioFerramentas, a pessoa é o `[Nome]` no título do PR.

### Ciclo de correção

Quando o Verifier ou o E2E encontram um problema, o relatório volta para o Builder:
- **Correção automática:** bug claro, com o comportamento certo escrito no spec.
- **Correção com a sua aprovação:** lacuna no spec, mudança de contrato ou BLOCK. A sua resposta entra em `## Decisions`.

A primeira correção retoma o mesmo Builder, que já tem o spec e o repositório no contexto. A segunda abre um Builder novo, porque depois de duas tentativas um contexto limpo rende mais. Em seguida o mesmo Verifier confere a correção, sem atacar de novo. São no máximo duas voltas; depois disso o branch volta para você com o último relatório.

### O que cada estágio pode tocar

O orquestrador compara o hash dos arquivos alterados antes e depois do Verifier e do E2E. O Verifier só pode ter criado arquivos `*.breaker.*`, e o E2E só arquivos de teste. Os hooks no frontmatter bloqueiam na hora; o diff pega o que passar. Uma violação para o run.

### Custo

Cada etapa grava tokens e tempo em `.pipeline/usage.csv`, que é arquivado com o run. Se o total passar de 450k tokens (800k com Planner), o pipeline para e pergunta se continua.

## Instalação

```bash
git clone https://github.com/Carloscavalcante97/pipeline-Claude.git
cd pipeline-Claude

# hooks dos agentes: ficam sempre neste caminho, que o frontmatter referencia
mkdir -p ~/.claude/hooks/pipeline && cp hooks/*.sh ~/.claude/hooks/pipeline/

# global, vale para todos os projetos da máquina
cp pipeline.md ~/.claude/commands/
cp agents/*.md ~/.claude/agents/

# ou só num projeto, versionado junto com o código dele
mkdir -p ../meu-projeto/.claude/commands ../meu-projeto/.claude/agents
cp pipeline.md ../meu-projeto/.claude/commands/
cp agents/*.md ../meu-projeto/.claude/agents/

# se você tinha a versão de oito agentes, remova o que saiu
rm -f ~/.claude/agents/{coder,tester,simplifier,reviewer}.md ~/.claude/commands/pipeline-v2.md
```

O Claude Code carrega comandos e agentes na inicialização: depois de copiar, reinicie. Hooks de agentes instalados dentro de um projeto só rodam depois que você aceita o diálogo de confiança do workspace; os globais rodam direto.

O plugin Ponytail no modo global pode ficar ligado. O Builder e o E2E Tester têm uma regra explícita para não reduzir os testes por critério.

## Como usar

Crie uma branch gitflow a partir da `develop` (ou da `main`, para hotfix) e rode o comando com uma descrição específica:

```bash
git switch develop && git pull
git switch -c feature/rate-limit-login
```

```
/pipeline "rate limiting em POST /auth/login: 5 tentativas por minuto por IP; na 6ª, 429 com {error: 'rate_limited'}; o contador zera depois de 60s"
```

Em `main`, `master` ou `develop` o pipeline para antes de começar. Se a árvore tiver alterações não commitadas, ele mostra a lista e pergunta se continua; essas alterações ficam fora dos commits do run.

Quanto mais completo o pedido, mais curto o run: um pedido que passa na triagem pula o Planner inteiro.

### Modelos de prompt

Uma boa descrição diz onde (rota, tela, endpoint, arquivo), o que muda de forma observável, a regra ou o limite, e o que acontece no erro. Se houver protótipo, aponte o arquivo ou a URL. O passo a passo para montar um pedido do zero está no [TUTORIAL.md](TUTORIAL.md).

```
/pipeline "<onde>: <o que muda>; <regra ou limite>; <o que acontece no erro>; protótipo em <caminho>"
```

Endpoint no backend (NestJS):

```
/pipeline "POST /orders: cria pedido a partir do carrinho do usuário logado; recusa carrinho vazio com 400 {error: 'empty_cart'}; só o dono do carrinho pode chamar (403 para outro usuário)"
```

Tela web (Next.js) com protótipo:

```
/pipeline "tela /configuracoes/perfil: formulário com nome (obrigatório) e telefone com máscara (99) 99999-9999; salva com PATCH /users/me e mostra o toast 'Perfil atualizado'; protótipo em docs/design/perfil.png"
```

Tela do app (React Native), testada no iPhone:

```
/pipeline "tela 'Esqueci a senha' no app: campo e-mail, botão Enviar desabilitado até o e-mail ser válido, e a mesma mensagem de sucesso para e-mail cadastrado ou não"
```

Regra de domínio sem tela nem rota (sem E2E; os testes do Builder e os ataques do Verifier são a verificação):

```
/pipeline "cupom de desconto no carrinho (src/cart.ts): novo método applyCoupon(code). 'DEZ' dá 10% de desconto no total; 'FRETE' desconta R$ 15,00. Código desconhecido lança InvalidCouponError; segundo cupom lança CouponAlreadyAppliedError. total() devolve o valor com desconto, arredondado a 2 casas"
```

Correção de bug (branch `bugfix/*`; o teste novo tem que reproduzir o bug no código atual):

```bash
git switch -c bugfix/login-500-proxy develop
```

```
/pipeline "corrigir: POST /auth/login devolve 500 quando a requisição passa pelo Nginx; o IP do rate limit deve vir do X-Forwarded-For, não do socket"
```

Hotfix em produção (branch a partir da `main`; o PR vai para a `main` e o Committer lembra de levar a correção de volta para a `develop`):

```bash
git switch -c hotfix/upload-foto main
```

```
/pipeline "corrigir: no app, foto de perfil acima de 5 MB trava o upload; recusar antes de enviar com a mensagem 'Imagem maior que 5 MB'"
```

Campo novo com migration:

```
/pipeline "adicionar data de nascimento ao usuário: coluna birth_date (date, opcional) via migration Prisma; aceitar no PATCH /users/me em ISO (AAAA-MM-DD); recusar data futura com 400 {error: 'invalid_birth_date'}"
```

### Descrição vaga e descrição específica

| O pipeline chama o Planner ou pede detalhe | Vai direto para o Builder |
|---|---|
| "adicionar rate limiting" | "rate limiting em POST /auth/login: 5/min por IP, 429 com {error: 'rate_limited'}" |
| "melhorar a tela de perfil" | "perfil: trocar o campo idade por data de nascimento (DD/MM/AAAA), salva em ISO no PATCH /users/me" |
| "arrumar o login do app" | "login do app: no erro auth/invalid-credential mostrar 'E-mail ou senha incorretos' em vez do toast genérico" |

### O que o pipeline pergunta durante o run

| Etapa | Pergunta | Quando |
|---|---|---|
| Setup | "Você já tem 2 PRs abertos neste projeto. Continuar? (s/n)" | você tem 2 PRs abertos no repo e esta branch ainda está sem PR |
| Setup | "A árvore tem alterações não commitadas. Continuar assim? (s/n)" | há trabalho seu não commitado |
| Triagem | "O pedido parece passar de ~500 linhas. Dividir em pedidos menores? (s/n)" | pedido grande |
| Planner | as perguntas em aberto do spec | a descrição deixou uma decisão em aberto |
| Builder / E2E | "Corrija o ambiente e rode de novo?" | banco fora, alvo que não é local, iPhone ausente, assinatura |
| E2E | "Conecte e desbloqueie o iPhone. Pronto? (s = iPhone / n = simulador)" | app React Native, uma vez por run |
| Ciclo de correção | "Aplicar esta correção? (s/n)" | lacuna no spec, mudança de contrato, BLOCK ou segunda volta (bug claro é corrigido sem perguntar) |
| Orçamento | "Passou do orçamento de tokens. Continuar? (s/n)" | mais de 450k tokens (800k com Planner) |
| Committer | "Commitar seguindo o gitflow? (s/n)" | só depois de SHIP |
| Committer | "Qual o seu nome para identificar os commits feitos pela conta AtomStudioFerramentas?" | conta compartilhada, só no primeiro commit da máquina |
| PR | "Abrir o PR agora? (s/n)" | a feature ou a tela está fechada, ou a branch chegou a 8 pontos (e você tem menos de 2 PRs abertos no repo) |

### Um run completo, resumido

Este é o run real da F02 (Idempotency-Key na compra) no flash-sales, com NestJS, Prisma e Vitest:

```
Triagem: 6 de 6 "sim". Planner pulado; o pedido vira o spec.
Builder: 18 testes. Red check 18/18 antes do código. Checks e testes novos ×3 verdes.
Verifier: 3 ataques contra a API rodando.
  1. 2000 requisições simultâneas (1000 chaves × 2), estoque 200: resistiu
  2. buyerId com surrogate UTF-16 solto: QUEBROU, a repetição idêntica dá 422 (bug)
  3. venda travada por 7 s: QUEBROU, a requisição com chave dá 500 (lacuna do spec)
Aplicar esta correção? (s/n) s   (lacuna decidida: esperar como a requisição sem chave)
Builder (retomado): os dois corrigidos, mais 1 teste.
Verifier (retomado): SHIP. Suíte e2e 74/74.

Commitar seguindo o gitflow? (s/n) s
  a38d792 feat(db): adicionar tabela de chaves de idempotência
  7ee70bb feat(sales): aceitar header Idempotency-Key na compra
  42cf25e test(sales): cobrir critérios de aceite da Idempotency-Key
  8699d73 test(sales): cobrir ataques de buyerId unicode e venda travada
Total: 4 chamadas de agente, 204k tokens, 18 min, 1 pergunta.
```

O agente direto, com o mesmo pedido, entregou o defeito do surrogate e precisou de uma rodada de correção depois da entrega.

## O que garante que os testes testam

O Builder escreve os testes antes do código, então eles têm que falhar antes de a feature existir. Um teste que passa sem a feature não a testa e é reescrito. Numa branch `bugfix/*`, isso prova que o teste reproduz o bug.

Os testes seguem estas regras:
- **Valores esperados:** são literais do spec (status, corpo, mensagem, contagem).
- **Isolamento:** cada teste cria os próprios dados e só confere esses dados, nunca contagens globais nem ordem. Na versão antiga, contagens globais criaram uma suíte instável que custou uma volta inteira de correção.
- **Proibidos:** snapshot, `skip`, `todo`, `only` e asserções vazias.
- **Instabilidade:** os testes novos rodam três vezes antes da entrega.

Um teste escrito por quem escreveu o código tende a confirmar o próprio código. Por isso o Verifier existe: ele ataca a partir do spec, não dos testes do Builder, e é aí que aparecem os defeitos que o oráculo não pega.

O spec tem uma seção de segurança, e cada item dela vira critério de aceite. O E2E nunca substitui o guard por `canActivate: () => true`.

## Gitflow e conta compartilhada

Rode sempre numa branch `feature/*`, `bugfix/*`, `hotfix/*` ou `release/*`, em letras minúsculas. Na conta compartilhada AtomStudioFerramentas, o primeiro commit pede o seu nome e os commits saem como `[Nome] feat(escopo): descrição`, para saber quem fez cada um. O nome fica salvo em `git config --global pipeline.commitAuthor`. Os commits e os PRs nunca levam linha de atribuição a ferramenta.

## App React Native no iPhone

O E2E de app React Native roda os flows do Maestro (`.maestro/*.yaml`) no iPhone físico. O Maestro oficial não dirige iPhone físico (a versão 2.11.0 recusa de propósito), então no aparelho os mesmos flows rodam com o [maestro-runner](https://github.com/devicelab-dev/maestro-runner) (`npx maestro-runner@1.1.28`). Sem iPhone conectado, o pipeline oferece rodar no simulador.

Uma vez por máquina e aparelho:

1. No iPhone, Ajustes → Privacidade e Segurança → Modo Desenvolvedor ligado. Conecte no cabo, desbloqueie e toque em Confiar. Durante os testes, Bloqueio Automático em Nunca.
2. No Xcode, Settings → Accounts, logado com o Apple ID do time.
3. No projeto, `"appleTeamId": "<TEAM_ID>"` dentro de `expo.ios` no `app.json` (ou `DEVELOPMENT_TEAM` já definido no projeto Xcode).
4. Confira com `npx maestro-runner@1.1.28 --platform ios doctor` e `npx maestro-runner@1.1.28 devices`; o iPhone tem que aparecer na lista.

Se o iOS bloquear o app do agente de teste na primeira execução: Ajustes → Geral → VPN e Gerenciamento de Dispositivos → confiar no certificado do time.

Cada critério testado termina com um print da tela, e cada falha gera o seu (`FALHOU-<flow>.png`). Tudo vai para `.pipeline/review/`, listado na seção Prints de `.pipeline/e2e-test-results.md`, para você conferir antes de responder ao commit. No fim do run a pasta é arquivada em `.pipeline/history/<run>/review/` e nunca entra em commit.

## Arquivos do run

| Arquivo em `.pipeline/` | Quem escreve | O que tem |
|---|---|---|
| `request.md` | orquestrador | o seu pedido, literal |
| `triage.md` | orquestrador | as seis respostas da triagem |
| `spec.md` | orquestrador (o pedido) ou Planner | o contrato e as decisões |
| `build.md` | Builder | critério por teste, red check, checks, arquivos, mapa do app |
| `e2e-test-results.md` | E2E Tester | modo, cobertura, prints, resultados |
| `verify.md` | Verifier | veredito, ataques, achados, o que corrigir |
| `commits.md` | Committer | commits feitos, o que ficou de fora, recomendação de PR |
| `usage.csv` | orquestrador | tokens e tempo de cada etapa |
| `history/` | orquestrador | um diretório por run e o `LOG.md` com o veredito de cada um |

## De oito agentes para dois

A primeira versão tinha oito estágios: Planner, Coder, Simplifier, Tester, Breaker, E2E, Reviewer e Committer. Ela foi medida no flash-sales (F01, estoque com reserva atômica) contra um agente direto. O oráculo empatou, mas a versão antiga usou 16 chamadas de agente, 951k tokens e 36 minutos, contra 155k tokens e 4 minutos do agente direto. O que se viu:

- **Breaker:** foi o único estágio que achou um defeito real, um byte NUL que virava 500, e o agente direto tinha entregado esse defeito.
- **Simplifier:** rodou três vezes e não mudou nada.
- **E2E:** repetiu os testes do Tester.
- **Ciclo de correção:** uma volta inteira serviu só para consertar a instabilidade que os testes do próprio pipeline criaram.
- **Spec do Planner:** 240 linhas, relidas por doze agentes.

As mudanças seguiram essas medições e o que a indústria e a pesquisa recomendam:
- **Planejar só pedido ambíguo.** [Anthropic, *Building effective agents*](https://www.anthropic.com/engineering/building-effective-agents) recomenda começar pelo mais simples, e o Codex e o Cursor só planejam tarefa complexa ou ambígua. Daí a triagem.
- **Testes e código num contexto só.** Separar em agentes diferentes só recarrega contexto, sem melhorar o resultado. Daí o Builder.
- **Verificação independente.** Testes escritos por outro agente acertam muito mais ([AgentCoder](https://arxiv.org/abs/2312.13010): 87,8% contra 61%), e um avaliador separado e cético funciona melhor que a autoavaliação ([Anthropic, 2026](https://www.anthropic.com/engineering/harness-design-long-running-apps)). Daí o Verifier.
- **Poucas tentativas de correção.** Os modelos perdem de 60% a 80% da capacidade de depurar em duas ou três tentativas ([DDI](https://arxiv.org/abs/2506.18403)). Daí o limite de duas voltas, com contexto novo na segunda.

O resultado foi a tabela do topo: sem o retrabalho do agente direto e com os mesmos tokens que ele. Os dados brutos, o protocolo e as ressalvas estão em `docs/experiment/` no flash-sales.

## Comandos úteis

```bash
cat .pipeline/history/LOG.md                         # histórico de todos os runs, com o veredito
column -ts, .pipeline/history/*/usage.csv            # tokens e tempo por etapa de cada run
git config --global --unset pipeline.commitAuthor    # trocar o nome salvo da conta compartilhada
npx maestro-runner@1.1.28 devices                    # o iPhone está visível para o teste?
open .pipeline/review                                # abrir os prints do E2E mobile no Finder
maestro test .maestro/                               # rodar os flows do app no simulador, fora do pipeline
```
