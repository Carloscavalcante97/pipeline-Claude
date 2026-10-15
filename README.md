# pipeline-Claude

**Pipeline de entrega spec-driven com 5 estágios de agentes IA — reduziu meu tempo de correção em ~75%.**

Um comando (`/pipeline <feature>`) transforma uma descrição de feature em código revisado e testado, passando por quatro subagentes especializados e um passe de simplificação, com **gates humanos** entre os estágios. Nenhum agente faz o trabalho do outro — e nenhum código chega à main sem passar por todos.

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
| 3 | **Tester** | Escreve e roda testes; **nunca** conserta o código | Falhou? Pipeline morre aqui, branch fica para o humano |
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

É um slash command do [Claude Code](https://claude.com/claude-code). Copie `pipeline.md` para `.claude/commands/` do seu projeto (junto com os subagentes `planner`, `coder`, `tester`, `e2e-tester`, `reviewer` e `committer` em `.claude/agents/`) e rode:

```
/pipeline "<descrição clara e específica da feature>"
```

Quanto mais específica a descrição, melhor o spec — e o pipeline recusa descrições vagas de propósito.

Rode sempre numa branch gitflow (`feature/*`, `bugfix/*`, `hotfix/*`, `release/*`). Na conta compartilhada **AtomStudioFerramentas**, o primeiro commit pede o seu nome e os commits saem como `[Nome] feat(escopo): descrição`, para saber quem fez cada um. O nome fica salvo em `git config --global pipeline.commitAuthor`.

---

*Antonio Carlos Cavalcante — [github.com/Carloscavalcante97](https://github.com/Carloscavalcante97)*
