# pipeline-Claude

Um comando do Claude Code, `/pipeline "<feature>"`, que transforma uma descrição de feature em código implementado, testado e revisado, passando por sete agentes especializados. Cada agente faz uma coisa só, e nenhum deles avalia o próprio trabalho. Entre os estágios há gates: o pipeline para quando falta uma decisão sua, quando um teste falha ou quando o review não aprova, e nunca faz commit, push ou merge sem você responder "s".

```
/pipeline "adicionar rate limiting em POST /login, 5 tentativas/min por IP, retornar 429"

  ┌──────────┐   ┌───────┐   ┌────────────┐   ┌────────┐   ┌─────┐   ┌──────────┐   ┌───────────┐
  │ Planner  │ → │ Coder │ → │ Simplifier │ → │ Tester │ → │ E2E │ → │ Reviewer │ → │ Committer │
  └──────────┘   └───────┘   └────────────┘   └────────┘   └─────┘   └──────────┘   └───────────┘
    spec.md      changes.md    simplifica    test-results  e2e-results  review.md    commits.md
       │             │                            │           │             │             │
   [perguntas]    [gate]                       [gate]      [gate]     SHIP / BLOCK    [s/n]
```

Em uso diário em sistemas NestJS/PostgreSQL, Next.js e .NET em produção, o tempo gasto em correção caiu cerca de 75% em comparação com um agente de IA solto.

## Por que existe

Um agente de IA sem processo produz código que parece pronto. O custo aparece depois, em correções, retrabalho e PRs que voltam. A causa quase sempre é uma destas duas: a entrada era ambígua, ou ninguém verificou a saída de forma independente.

O pipeline ataca as duas pontas. Antes de qualquer código, o Planner transforma a feature em um spec com critérios de aceite numerados; se sobrar uma decisão que só você pode tomar, o pipeline para e pergunta. Depois do código, quem testa e quem revisa são agentes diferentes de quem escreveu, sem permissão para consertar o que encontram. Um teste que não falha sem a feature é reescrito, e typecheck, lint, build e a suíte completa do projeto rodam a cada run.

## Como funciona

Os agentes se comunicam apenas por arquivos na pasta `.pipeline/` do projeto. Cada estágio lê os arquivos dos anteriores e deixa o seu. No fim do run tudo é arquivado em `.pipeline/history/`, com uma linha no `LOG.md`, então o histórico de decisão de cada feature sobrevive.

### 1. Planner

Lê o pedido e explora o repositório para entender os padrões existentes. Escreve `.pipeline/spec.md`: arquivos a mudar, assinaturas, critérios de aceite numerados e falsificáveis, casos de borda, uma seção de segurança (quem pode chamar, o que é validado, o que sai do sistema) e o que fica fora do escopo. Não escreve código. Quando o pedido deixa uma decisão em aberto, ele a registra como pergunta e o pipeline para. Você responde, ele grava as respostas em `## Decisions` e o run continua.

### 2. Coder

Implementa o spec, e só o spec. Roda typecheck, lint e build do projeto e registra os resultados em `.pipeline/changes.md`. Um hook impede que ele edite arquivos de teste. Não adiciona dependência que o spec não lista, não coloca segredo em código e não usa supressões (`eslint-disable`, `@ts-ignore`, `as any`) para ficar verde. Se encontrar uma pergunta aberta ou um spec impossível, para e diz por quê.

### 2.5 Simplifier

Passa a régua do Ponytail no diff do Coder: abstração com uma implementação só, configuração para um valor que nunca muda, código morto, dependência nova para o que poucas linhas resolvem. Só mexe em código de produto. Antes de seguir, roda o typecheck e os testes existentes; se uma simplificação quebrar algo, ele mesmo desfaz.

### 3. Tester

Escreve um teste para cada critério de aceite, caso de borda e item de segurança do spec, com os valores esperados copiados do spec, nunca da saída do código. Depois prova que os testes testam a feature: copia os arquivos novos para uma cópia do código em `HEAD`, onde a feature ainda não existe, e eles têm que falhar lá. Em seguida roda a suíte completa, typecheck, lint e build; qualquer exit diferente de 0 é falha do run. Nunca conserta o código. Um hook só deixa editar arquivos de teste.

### 3.5 E2E Tester

Testa o sistema rodando. Playwright para tela web, supertest para API, Maestro para app React Native (no iPhone ou no simulador). Antes de qualquer comando que toque banco ou API, imprime o alvo e exige que seja local ou de teste; produção é `blocked`. Para cada rota protegida, testa sem token (401) e com o token de outro usuário (403 ou 404), sem substituir o guard. No app, cada critério termina com um print em `.pipeline/review/`. Quando a mudança não tem superfície para dirigir (uma classe interna, por exemplo), o status é `n/a`.

### 4. Reviewer

Lê o pedido original, o spec, o diff real, os arquivos de teste inteiros (as tabelas de cobertura sozinhas não bastam) e os prints. É somente leitura: não tem ferramenta de edição e um hook bloqueia qualquer comando de shell que escreva. Emite o veredito: SHIP, NEEDS WORK ou BLOCK. Um teste que passa sem a feature, um critério sem teste ou um typecheck que falhou são achados, mesmo com tudo verde.

### 5. Committer

Só roda depois de um SHIP e de você responder "s". Divide o trabalho em commits pequenos por camada, em ordem de dependência, no padrão Conventional Commits. Na conta compartilhada AtomStudioFerramentas, prefixa cada commit com `[Nome]`. Antes de cada commit, procura segredos no conteúdo dos arquivos (chave privada, AKIA, tokens, `password: "..."`) e para se achar. Nunca commita o que já estava alterado antes do run. Depois avalia se é hora de abrir o PR (tela fechada, feature fechada, branch grande, hotfix) e, com outro "s", abre.

### Ciclo de correção

Quando um teste falha ou o review não dá SHIP, o Planner diagnostica a causa raiz e anexa um Fix Plan ao spec: o que o Coder muda, o que o Tester muda (quase sempre nada; um teste só é considerado errado quando contradiz uma linha do spec) e o que ninguém deve tocar. Nada acima do Fix Plan pode mudar, e o orquestrador confere isso com um diff. Você vê a falha e o plano, e decide se aplica. Com o "s", rodam Coder, Simplifier, Tester, E2E e Reviewer de novo. No máximo duas voltas; depois disso o branch volta para você com o último relatório.

### O que cada estágio pode tocar

O orquestrador compara o hash dos arquivos alterados antes e depois de cada estágio. O Simplifier não pode ter mudado teste, os testers só podem ter mudado teste, e o Reviewer não pode ter mudado nada. Os hooks no frontmatter dos agentes bloqueiam a ação na hora; o diff pega o que passar. Uma violação para o run.

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
```

O Claude Code carrega comandos e agentes na inicialização: depois de copiar, reinicie. Hooks de agentes instalados dentro de um projeto só rodam depois que você aceita o diálogo de confiança do workspace; os globais rodam direto.

Se você usa o plugin Ponytail no modo global, inicie o Claude Code com `PONYTAIL_DEFAULT_MODE=off` para rodar o pipeline. O modo global é injetado em todos os subagentes, inclusive no Tester, que ele manda minimizar testes. O Simplifier carrega a skill sozinho.

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

### Modelos de prompt

Uma boa descrição diz onde (rota, tela, endpoint, arquivo), o que muda de forma observável, a regra ou o limite, e o que acontece no erro. Se houver protótipo, aponte o arquivo ou a URL.

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

Regra de domínio sem tela nem rota (o E2E dá `n/a` e a suíte unitária é a verificação):

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

| O pipeline para e pede detalhe | Vira spec direto |
|---|---|
| "adicionar rate limiting" | "rate limiting em POST /auth/login: 5/min por IP, 429 com {error: 'rate_limited'}" |
| "melhorar a tela de perfil" | "perfil: trocar o campo idade por data de nascimento (DD/MM/AAAA), salva em ISO no PATCH /users/me" |
| "arrumar o login do app" | "login do app: no erro auth/invalid-credential mostrar 'E-mail ou senha incorretos' em vez do toast genérico" |

### O que o pipeline pergunta durante o run

| Etapa | Pergunta | Quando |
|---|---|---|
| Setup | "A árvore tem alterações não commitadas. Continuar assim? (s/n)" | há trabalho seu não commitado |
| Planner | as perguntas em aberto do spec | a descrição deixou uma decisão em aberto |
| Tester / E2E | "Corrija o ambiente e rode de novo?" | banco fora, alvo que não é local, iPhone ausente, assinatura |
| E2E | "Conecte e desbloqueie o iPhone. Pronto? (s = iPhone / n = simulador)" | app React Native, uma vez por run |
| Ciclo de correção | "Aplicar esta correção? (s/n)", depois de mostrar a falha e o Fix Plan | teste falhou ou o review não deu SHIP |
| Committer | "Commitar seguindo o gitflow? (s/n)" | só depois de SHIP |
| Committer | "Qual o seu nome para identificar os commits feitos pela conta AtomStudioFerramentas?" | conta compartilhada, só no primeiro commit da máquina |
| PR | "Abrir o PR agora? (s/n)" | a feature ou a tela está fechada |

### Um run completo, resumido

Este é o run real do exemplo do cupom, num projeto TypeScript com Jest:

```
Planner: spec com 19 critérios de aceite e 2 perguntas em aberto.
  1. FRETE num total abaixo de 15,00: (a) trava em 0  (b) rejeita com erro  (c) deixa negativo
  2. Arredondamento em meio centavo (10,05 × 0,9 = 9,045): (a) comercial, 9,05  (b) ABNT 5891, 9,04
Você responde: 1a, 2a. O Planner registra em ## Decisions e segue.

Coder: src/cart.ts (+22 linhas). typecheck 0, build 0.
Simplifier: nada a cortar; cada trecho corresponde a um critério.
Tester: 36 testes novos. Red check: todos falham em HEAD. Suíte completa 38/38. typecheck e build 0.
E2E: n/a (classe em memória, sem rota nem tela).
Reviewer: SHIP, nenhum achado.

Commitar seguindo o gitflow? (s/n) s
  b599db1 feat(cart): adicionar cupom de desconto no carrinho
  f551a14 test(cart): cobrir cupons, erros e arredondamento do total
PR recomendado (feature fechada): feat(cart): cupom de desconto no carrinho → develop
Abrir o PR agora? (s/n)
```

E o mesmo run com uma regressão injetada no `cart.ts` antes do Tester, para mostrar o ciclo de correção:

```
Tester: FAILURES. 1 de 38: "FRETE never makes the total negative", esperado 0, recebido -0.01.
Planner (fix): causa raiz em src/cart.ts:31, faltou o Math.max(0, ...) da Decision 1.
  Mudanças para o Coder: uma linha. Para o Tester: nenhuma, o teste está certo.
Aplicar esta correção? (s/n) s
Coder: uma linha, arquivo volta ao hash revisado. Simplifier: nada. Tester: 38/38.
```

## O que garante que os testes testam

Na hora do Tester nada foi commitado, então `HEAD` é o código sem a feature. Cada teste novo roda ali e tem que falhar. Um teste que passa sem a feature não a testa e é reescrito. Numa branch `bugfix/*`, isso prova que o teste reproduz o bug.

Os valores esperados são literais do spec: status, corpo, mensagem, contagem. Mock de acesso a dados tem os argumentos assertados. Snapshot, `skip`, `todo`, `only` e asserções vazias (`toBeDefined()` sozinho) são proibidos, e o relatório inclui as linhas do runner por arquivo, para provar que cada arquivo novo rodou.

O spec tem uma seção de segurança e cada item dela vira critério de aceite, então o unitário e o E2E cobrem autorização e validação. O E2E nunca substitui o guard por `canActivate: () => true`.

O Reviewer recebe o pedido original junto com o spec. Se o Planner leu "por IP" como "por e-mail", a implementação perfeita do spec errado é bloqueada.

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

Cada critério testado termina com um print da tela, e cada falha gera o seu (`FALHOU-<flow>.png`). Tudo vai para `.pipeline/review/`, listado na seção Prints de `.pipeline/e2e-test-results.md`. O Reviewer olha esses prints antes do veredito. No fim do run a pasta é arquivada em `.pipeline/history/<run>/review/` e nunca entra em commit.

## Arquivos do run

| Arquivo em `.pipeline/` | Quem escreve | O que tem |
|---|---|---|
| `request.md` | orquestrador | o seu pedido, literal |
| `spec.md` | Planner | o contrato: critérios, segurança, decisões, Fix Plans |
| `changes.md` | Coder e Simplifier | o que mudou, checks estáticos, o que foi simplificado |
| `test-results.md` | Tester | status, red check, checks estáticos, cobertura, resultados |
| `e2e-test-results.md` | E2E Tester | modo, cobertura, prints, resultados |
| `review.md` | orquestrador, com o texto do Reviewer | veredito e achados |
| `commits.md` | Committer | commits feitos, o que ficou de fora, recomendação de PR |
| `history/` | orquestrador | um diretório por run e o `LOG.md` com o veredito de cada um |

## Comandos úteis

```bash
cat .pipeline/history/LOG.md                         # histórico de todos os runs, com o veredito
git config --global --unset pipeline.commitAuthor    # trocar o nome salvo da conta compartilhada
npx maestro-runner@1.1.28 devices                    # o iPhone está visível para o teste?
open .pipeline/review                                # abrir os prints do E2E mobile no Finder
maestro test .maestro/                               # rodar os flows do app no simulador, fora do pipeline
```

*Antonio Carlos Cavalcante, [github.com/Carloscavalcante97](https://github.com/Carloscavalcante97)*
