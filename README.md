# pipeline-Claude

**Pipeline de entrega spec-driven com 5 estágios de agentes IA — reduziu meu tempo de correção em ~75%.**

Um comando (`/pipeline <feature>`) transforma uma descrição de feature em código revisado e testado, passando por seis subagentes especializados e um passe de simplificação, com **gates humanos** entre os estágios. Nenhum agente faz o trabalho do outro — e nenhum código chega à main sem passar por todos.

```
/pipeline "adicionar rate limiting em POST /login, 5 tentativas/min por IP, retornar 429"

  ┌──────────┐   ┌───────┐   ┌──────────┐   ┌────────┐   ┌──────────┐   ┌───────────┐
  │ Planner  │ → │ Coder │ → │ Ponytail │ → │ Tester │ → │ Reviewer │ → │ Committer │
  └──────────┘   └───────┘   └──────────┘   └────────┘   └──────────┘   └───────────┘
    spec.md      changes.md   simplifica    test-results   review.md     commits.md
       │             │                          │             │              │
     [gate]        [gate]                     [gate]     SHIP / BLOCK   [gate s/n]
```

## Por que isso existe

Agente de IA sem processo produz código que *parece* pronto. O custo aparece depois: correções, retrabalho, PRs que voltam. A causa quase sempre é a mesma — **ambiguidade na entrada e ausência de verificação independente na saída**.

O pipeline ataca as duas pontas:

- **Spec antes de código.** O Planner converte a feature em um spec preciso (`.pipeline/spec.md`). Se sobra qualquer pergunta em aberto, o pipeline **para** e um humano responde. Requisito vago nunca chega ao Coder.
- **Quem escreve não se avalia.** Coder implementa exatamente o spec. Tester escreve e roda os testes — e é proibido de consertar o código. Reviewer é read-only por design: emite veredito (SHIP / NEEDS WORK / BLOCK) sem poder editar nada.
- **Simplificação como estágio, não como esperança.** Entre Coder e Tester, um passe "Ponytail" caça over-engineering: abstrações especulativas, código morto, dependência desnecessária. O diff mais curto que funciona é o que segue adiante.

## Os 5 estágios

| # | Estágio | Faz | Gate de saída |
|---|---------|-----|---------------|
| 1 | **Planner** | Feature → spec de implementação (`spec.md`), sem escrever código | Perguntas em aberto? Para e pergunta ao humano |
| 2 | **Coder** | Implementa exatamente o spec, registra handoff em `changes.md` | Status ≠ `implemented`? Para e reporta |
| 2.5 | **Ponytail** | Revisa o diff por over-engineering e simplifica in-place | Sempre prossegue (anota o que cortou) |
| 3 | **Tester** | Escreve e roda testes; **nunca** conserta o código | Falhou? Ciclo de correção liderado pelo Planner, com o seu ok |
| 3.5 | **E2E Tester** | Testa o sistema rodando: Playwright (web), HTTP (API) ou Maestro no iPhone (React Native); **nunca** conserta o código | Falhou? Ciclo de correção. Problema de ambiente (sem iPhone, assinatura)? Para e pergunta |
| 4 | **Reviewer** | Review read-only do spec + diff + testes; veredito final | SHIP / NEEDS WORK / BLOCK |
| 5 | **Committer** | Só após SHIP e com o seu "s": divide o trabalho em commits pequenos no padrão gitflow + Conventional Commits e recomenda abrir o PR quando a feature ou tela está fechada | Pergunta antes de commitar e antes de abrir o PR |

Os agentes se comunicam **apenas por arquivos** em `.pipeline/` — cada estágio deixa um handoff auditável. Runs anteriores são arquivados em `.pipeline/history/`, então todo o histórico de decisão sobrevive.

## Princípios

1. **Gates > vibes.** O pipeline para em ambiguidade, em implementação incompleta e em teste falhando. Falhar cedo e barato é o objetivo, não o problema.
2. **Separação de poderes.** Ferramentas de escrita são retiradas de quem revisa. Não é confiança — é arquitetura.
3. **Humano nos pontos de decisão.** O pipeline nunca faz merge. Commit e push só acontecem depois de um SHIP e de um "s" explícito seu — a decisão é sua.
4. **Handoffs legíveis.** Ler os `.pipeline/*.md` de cada run ensina a escrever descrições de feature cada vez mais afiadas.

## Resultado

Em uso diário no meu trabalho (sistemas NestJS/PostgreSQL, Next.js e .NET em produção): **~75% menos tempo gasto em correção** comparado a usar um agente de IA "solto". Escrevo e apresento internamente sobre esse fluxo.

## Uso

É um slash command do [Claude Code](https://claude.com/claude-code):

```
/pipeline "<descrição clara e específica da feature>"
```

Quanto mais específica a descrição, melhor o spec — e o pipeline recusa descrições vagas de propósito.

### Instalação

```bash
git clone https://github.com/Carloscavalcante97/pipeline-Claude.git
cd pipeline-Claude

# só num projeto (versionado junto com o código dele)
mkdir -p ../meu-projeto/.claude/commands ../meu-projeto/.claude/agents
cp pipeline.md ../meu-projeto/.claude/commands/
cp agents/*.md ../meu-projeto/.claude/agents/

# ou global: vale para todos os projetos desta máquina
cp pipeline.md ~/.claude/commands/
cp agents/*.md ~/.claude/agents/
```

Se o `/pipeline` ou os agentes não aparecerem, reinicie o Claude Code — eles são carregados na inicialização.

### Exemplos

Todo run começa numa branch gitflow, criada a partir da `develop`:

```bash
git switch develop && git pull
git switch -c feature/rate-limit-login
```

**Endpoint no backend (NestJS)**

```
/pipeline "rate limiting em POST /auth/login: 5 tentativas por minuto por IP; na 6ª, 429 com {error: 'rate_limited'}; o contador zera depois de 60s"
```

**Tela web (Next.js) com protótipo**

```
/pipeline "tela /configuracoes/perfil: formulário com nome (obrigatório) e telefone com máscara (99) 99999-9999; salva com PATCH /users/me e mostra o toast 'Perfil atualizado'; protótipo em docs/design/perfil.png"
```

O protótipo vira a referência de estilo que o E2E confere com Playwright.

**Tela do app (React Native) testada no iPhone**

```
/pipeline "tela 'Esqueci a senha' no app: campo e-mail, botão Enviar desabilitado até o e-mail ser válido, e a mesma mensagem de sucesso para e-mail cadastrado ou não"
```

Na etapa de E2E o pipeline pede para conectar o iPhone; responda `n` para rodar no simulador. A configuração do aparelho está em [App React Native no iPhone](#app-react-native-no-iphone).

**Correção de bug**

```bash
git switch -c bugfix/login-500-proxy develop
```

```
/pipeline "corrigir: POST /auth/login devolve 500 quando a requisição passa pelo Nginx; o IP do rate limit deve vir do X-Forwarded-For, não do socket"
```

**Hotfix em produção**

```bash
git switch -c hotfix/upload-foto main
```

```
/pipeline "corrigir: no app, foto de perfil acima de 5 MB trava o upload; recusar antes de enviar com a mensagem 'Imagem maior que 5 MB'"
```

O PR do hotfix vai para a `main`, e o Committer lembra de levar a correção de volta para a `develop`.

### Descrição vaga × específica

| ❌ O pipeline para e pede detalhe | ✅ Vira spec direto |
|---|---|
| "adicionar rate limiting" | "rate limiting em POST /auth/login: 5/min por IP, 429 com {error: 'rate_limited'}" |
| "melhorar a tela de perfil" | "perfil: trocar o campo idade por data de nascimento (DD/MM/AAAA), salva em ISO no PATCH /users/me" |
| "arrumar o login do app" | "login do app: no erro auth/invalid-credential mostrar 'E-mail ou senha incorretos' em vez do toast genérico" |

Diga **onde** (rota, tela, endpoint), **o quê** (comportamento que dá para observar) e **o que acontece no erro**.

### O que o pipeline pergunta durante o run

| Etapa | Pergunta | Quando |
|---|---|---|
| Planner | as *Open Questions* do spec | a descrição deixou uma decisão em aberto |
| E2E | "Conecte e desbloqueie o iPhone… Pronto? (s = iPhone / n = simulador)" | app React Native, uma vez por run |
| Ciclo de correção | "Run a fix iteration on this? (y/n)" | teste falhou ou o review não deu SHIP (no máximo 2 voltas) |
| Committer | "Commitar seguindo o gitflow? (s/n)" | só depois de SHIP |
| Committer | "Qual o seu nome para identificar os commits feitos pela conta AtomStudioFerramentas?" | conta compartilhada, só no primeiro commit da máquina |
| PR | "Abrir o PR agora? (s/n)" | a feature ou a tela está fechada |

### Exemplo do fim de um run

```
Veredito: SHIP
Commitar seguindo o gitflow? (s/n) s

Commits em feature/tela-login (conta AtomStudioFerramentas):
  4848e9a [Antonio] build(deps): adicionar @nestjs/throttler
  d5933d4 [Antonio] feat(db): adicionar email e senha ao usuário
  4897bac [Antonio] feat(auth): adicionar endpoint POST /auth/login
  cc98511 [Antonio] feat(login): adicionar tela /login
  604564f [Antonio] test(auth): cobrir login válido e inválido
  d3b6518 [Antonio] test(e2e): validar redirecionamento do login
Fora dos commits: notes.txt (já estava alterado antes do run), .env (segredo)

PR recomendado — tela fechada: /login navegável e com E2E passando
  [Antonio] feat(login): tela de login com email e senha → develop
Abrir o PR agora? (s/n)
```

### Gitflow e conta compartilhada

Rode sempre numa branch gitflow (`feature/*`, `bugfix/*`, `hotfix/*`, `release/*`); em `main`, `master` ou `develop` o pipeline para antes de começar. Na conta compartilhada **AtomStudioFerramentas**, o primeiro commit pede o seu nome e os commits saem como `[Nome] feat(escopo): descrição`, para saber quem fez cada um. O nome fica salvo em `git config --global pipeline.commitAuthor`.

### App React Native no iPhone

O E2E de app React Native roda os flows do Maestro (`.maestro/*.yaml`) no iPhone físico. O Maestro oficial não dirige iPhone físico (a 2.11.0 recusa de propósito), então no aparelho os mesmos flows rodam com o [maestro-runner](https://github.com/devicelab-dev/maestro-runner) (`npx maestro-runner@1.1.28`). Sem iPhone conectado, o pipeline oferece rodar no simulador com o Maestro.

Uma vez por máquina e aparelho:

1. **iPhone:** Ajustes → Privacidade e Segurança → **Modo Desenvolvedor** ligado. Conecte no cabo, desbloqueie e toque em **Confiar**. Durante os testes, Bloqueio Automático em **Nunca**.
2. **Xcode** → Settings → Accounts: logado com o Apple ID do time.
3. **Projeto:** `"appleTeamId": "<TEAM_ID>"` dentro de `expo.ios` no `app.json` (ou `DEVELOPMENT_TEAM` já definido no projeto Xcode).
4. **Conferir:** `npx maestro-runner@1.1.28 --platform ios doctor` e `npx maestro-runner@1.1.28 devices` — o iPhone tem que aparecer na lista.

Se o iOS bloquear o app do agente de teste na primeira execução: Ajustes → Geral → VPN e Gerenciamento de Dispositivos → confiar no certificado do time.

**Prints para validar.** Cada critério testado termina com um print da tela, e cada falha também gera o seu (`FALHOU-<flow>.png`). Tudo vai para `.pipeline/review/`, listado na seção *Prints* de `.pipeline/e2e-test-results.md`. O Reviewer também olha esses prints antes do veredito. No fim do run a pasta é arquivada em `.pipeline/history/<run>/review/` e nunca entra em commit.

### Comandos úteis

```bash
cat .pipeline/history/LOG.md                         # histórico de todos os runs, com o veredito
git config --global --unset pipeline.commitAuthor    # trocar o nome salvo da conta compartilhada
npx maestro-runner@1.1.28 devices                    # o iPhone está visível para o teste?
open .pipeline/review                                # abrir os prints do E2E mobile no Finder
maestro test .maestro/                               # rodar os flows do app no simulador, fora do pipeline
```

---

*Antonio Carlos Cavalcante — [github.com/Carloscavalcante97](https://github.com/Carloscavalcante97)*
