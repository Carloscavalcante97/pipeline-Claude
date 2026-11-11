# Tutorial: como escrever um bom pedido para o `/pipeline`

O pedido que você passa ao `/pipeline` é a única coisa do run que vem de você. Todo o resto sai dele. O Planner transforma o pedido no spec, o Coder implementa o spec, o Tester testa o spec, e o Reviewer compara o resultado com o pedido literal. Um pedido vago vira um spec cheio de perguntas, ou pior, um spec que adivinhou errado e foi implementado com perfeição.

Este tutorial mostra como montar um pedido que vira spec direto, sem rodadas de pergunta e sem retrabalho.

## As sete partes de um bom pedido

Nem todo pedido precisa de todas. As quatro primeiras quase sempre aparecem.

| Parte | Pergunta que responde | Vira, no spec |
|---|---|---|
| **Onde** | Qual rota, tela, endpoint ou arquivo? | Files to create / modify, Existing pattern |
| **O que muda** | O que fica diferente, de forma que dá para ver ou medir? | Goal, Acceptance criteria |
| **Regra ou limite** | Qual o número, o formato, a condição? | Acceptance criteria, Edge cases |
| **Erro** | O que acontece quando dá errado? Com qual status e mensagem? | Acceptance criteria, Edge cases |
| **Quem pode** | Precisa estar logado? Qual papel? Só o dono do recurso? | Security, e um critério de aceite para cada regra |
| **Protótipo** | Tem Figma, print ou página de referência? | Prototype / design reference |
| **Fora do escopo** | O que parece fazer parte mas não é para fazer agora? | Out of scope |

O molde fica assim.

```
/pipeline "<onde>: <o que muda>; <regra ou limite>; <o que acontece no erro>; <quem pode>; protótipo em <caminho>; fora do escopo <x>"
```

## Passo a passo, do vago ao específico

Vamos montar um pedido real partindo da ideia solta.

**Ponto de partida.** "Quero que o usuário possa favoritar produtos."

Isso roda, mas o Planner vai parar com várias perguntas. Onde fica o botão? Tem limite? Quem vê os favoritos? Cada pergunta é uma rodada a mais.

**1. Diga onde.** Nomeie a rota ou a tela como ela existe no código.

```
POST /products/:id/favorite e DELETE /products/:id/favorite
```

**2. Diga o que muda de forma observável.** Descreva o comportamento, não a implementação. "Salva na tabela favorites" é implementação. "GET /users/me/favorites passa a listar o produto" é comportamento, e o Tester consegue verificar.

```
o produto passa a aparecer em GET /users/me/favorites, do mais recente para o mais antigo
```

**3. Diga a regra ou o limite.** Número, formato, condição. Sem adjetivo.

```
favoritar duas vezes não duplica (continua 1 registro, responde 200); máximo de 100 favoritos por usuário
```

**4. Diga o que acontece no erro.** Status e corpo exatos. O Tester copia esse texto para o teste, então escreva como quer que fique.

```
produto inexistente: 404 {error: 'product_not_found'}; acima de 100: 422 {error: 'favorites_limit'}
```

**5. Diga quem pode.** Isso vira a seção de segurança e um critério de aceite para cada regra, e é o que faz o E2E testar sem token e com o token de outro usuário.

```
só usuário logado; cada um vê e mexe só nos próprios favoritos
```

**6. Corte o que não é agora.** Se você sabe que alguém vai pensar nisso, diga que fica de fora.

```
fora do escopo: botão na tela (vem em outra task)
```

**Resultado.**

```
/pipeline "favoritos de produto: POST /products/:id/favorite e DELETE /products/:id/favorite; o produto passa a aparecer em GET /users/me/favorites, do mais recente para o mais antigo; favoritar duas vezes não duplica (responde 200); máximo de 100 por usuário; produto inexistente dá 404 {error: 'product_not_found'}, acima de 100 dá 422 {error: 'favorites_limit'}; só usuário logado, cada um vê e mexe só nos próprios favoritos; fora do escopo o botão na tela"
```

Longo, sim. Mas cada trecho vira um critério de aceite que alguém vai testar, e nenhum deles precisou de pergunta.

## Pedido por task do Journify

Se a feature já está numa task do Journify, passe o ID ou o link.

```
/pipeline IukG491JBKEkvjmeT8yg
```

O pipeline lê o título, a descrição e os comentários da task e usa isso como pedido. Então a task **é** o prompt, e as mesmas sete partes valem para ela. Uma task bem escrita tem os critérios numerados na descrição, porque o PR Creator monta o plano de testes do robô a partir deles (C1, C2...).

Quando a task não diz tudo, complete depois do ID. As notas entram no pedido junto com a task.

```
/pipeline IukG491JBKEkvjmeT8yg "o limite é 100 por usuário; produto inexistente dá 404 {error: 'product_not_found'}"
```

Se a mesma lacuna aparecer sempre, o melhor é corrigir a task, não as notas. Assim o revisor de regras e o robô de testes também enxergam.

## Checklist antes de rodar

- [ ] Estou numa branch `feature/*`, `bugfix/*`, `hotfix/*` ou `release/*`?
- [ ] O pedido nomeia a rota, a tela ou o arquivo como existe no código?
- [ ] Cada comportamento é algo que dá para ver ou medir?
- [ ] Os limites têm número e os formatos têm exemplo (`DD/MM/AAAA`, `(99) 99999-9999`)?
- [ ] Os erros têm status e mensagem exatos?
- [ ] Disse quem pode chamar ou ver?
- [ ] Apontei o protótipo, se for tela?
- [ ] É **uma** feature? Se tem um "e também", são dois runs.

## Erros comuns

| Em vez de | Escreva |
|---|---|
| Adjetivo ("rápido", "bonito", "seguro") | O número ou a regra ("responde em menos de 300 ms", "botão #2563EB, raio 8px", "só o dono, 404 para outro usuário") |
| Implementação ("cria um service", "usa Redis") | O comportamento observável. O Planner escolhe a implementação seguindo o padrão do projeto |
| "mostra uma mensagem de erro" | A mensagem exata entre aspas |
| "etc", "e afins", "coisas do tipo" | A lista completa. O que não está escrito não vira teste |
| Duas features num pedido | Dois runs, cada um com o seu PR |
| "corrigir o login" | O sintoma, onde acontece e o comportamento certo ("POST /auth/login devolve 500 atrás do Nginx; o IP deve vir do X-Forwarded-For") |

## Respondendo às perguntas do Planner

Mesmo um bom pedido pode deixar uma decisão em aberto. O Planner para e pergunta, normalmente com opções.

```
1. FRETE num total abaixo de 15,00: (a) trava em 0  (b) rejeita com erro  (c) deixa negativo
```

Responda curto e sem ambiguidade (`1a`). A resposta vai para `## Decisions` no spec e vira critério de aceite, então ela vale tanto quanto o pedido. Se nenhuma opção serve, escreva a regra que você quer com a mesma precisão do pedido.

Se o Planner perguntar algo que você achava óbvio, é sinal de que o pedido deixou isso implícito. Na próxima vez, ponha no pedido. O `.pipeline/history/LOG.md` ajuda a ver quais perguntas se repetem.

## Resumo

Um bom pedido diz **onde**, **o que muda**, **a regra**, **o erro** e **quem pode**, com números e mensagens exatas, e corta o que não é agora. Escreva como se cada trecho fosse virar um teste, porque vai.

Para mais exemplos prontos (tela web, app, regra de domínio, bugfix, hotfix, migration), veja [Modelos de prompt](README.md#modelos-de-prompt) no README.
