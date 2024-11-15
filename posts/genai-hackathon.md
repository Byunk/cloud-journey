---
title: "사내 Gen AI 해커톤 회고"
excerpt: "사내에서 진행한 Generative AI 해커톤에 참여했다."
date: "2024-11-15"
draft: true
---

- [개요](#개요)
- [주제](#주제)
  - [`mxGraph`](#mxgraph)
- [Method](#method)
  - [어떤게 좋은 다이어그램인가?](#어떤게-좋은-다이어그램인가)
  - [Image Input](#image-input)
  - [Few-shots](#few-shots)
  - [Chain of Thougths](#chain-of-thougths)
  - [새로운 데이터 형태 제시](#새로운-데이터-형태-제시)
- [결과](#결과)
- [Reference](#reference)

## 개요

사내에서 글로벌하게 진행한 Generative AI 해커톤에 참여했다. 나를 포함해 네 명의 팀원으로 구성했고, 개발자 세 명과 디자이너 한 명으로 이루어진 팀이었다.

## 주제

입사한 이후 일 년동안 내 리소스를 가장 많이 투자한 부분 중 하나는 커뮤니케이션이었다. 우리 팀은 커뮤니케이션을 위해 다이어그램을 자주 활용하는데, 주니어 개발자의 입장에서 효과적이고 명확한 다이어그램을 그리는 일은 매우 어려운 일이다. 그 이유 중 하나는 다이어그램은 과학의 영역보다는 예술의 영역에 가깝기 때문이다. 다이어그램을 그리기 위한 syntax (UML, TAM, ...)은 최소한의 규칙만을 정의하고 아이디어를 어떻게 표현할 것인지, 어느정도의 추상화 단계까지 그릴 것인지, 컴포넌트의 배치를 어떻게 할 것인지에 대한 규칙은 오로지 다이어그램을 그리는 개발자의 몫이다.

또 다른 문제점은 다이어그램을 그리는 과정 자체가 많은 단순 반복성 작업을 수반한다는 점이다. 아무리 경험 많은 시니어 개발자라고 하더라도 다이어그램의 syntax를 지키기 위해 여러 반복 작업을 수행해야 한다. 예를 들어, [TAM diagram style](https://community.sap.com/t5/technology-blogs-by-sap/how-to-communicate-architecture-technical-architecture-modeling-at-sap-part/ba-p/13065457)은 request/response를 방향이 없는 화살표 + 문자 'R' + 꺽쇠의 조합으로 표현한다. 이를 그리는 과정은 Draw.io 혹은 Lucid Chart와 같은 도구를 이용한다고 하더라도 상당한 피로감을 준다. 더군다나, 경험상 다이어그램을 그리는 과정에서 자주 배치를 변경하거나 화살표를 다시 그리는 일이 발생하기 때문에 이러한 반복 작업은 상당히 자주 일어난다.

따라서 내가 생각한 해결책은 이러한 반복 작업을 gen AI (이하 LLM)을 통해 줄이고, 자연어 입력 값을 챗봇 형태로 받으면서 수정해주는 도구를 제작하는 것이었다. Draw.io와 같은 도구는 다이어그램을 XML과 같은 텍스트 데이터로 표현하기 때문에 LLM에게 이를 이해시키는 것이 가능할 것으로 보였다. 특히, GPT-4o 같은 최신의 모델 같은 경우에는 Draw.io가 사용하는 `mxGraph` syntax를 이미 잘 이해하고 있는 것으로 보였기 때문에 시도해보는 것이 의미 있을 것이라고 가정했다.

### `mxGraph`

`mxGraph` syntax는 아래와 같이 좌표를 이용해 컴포넌트의 위치를 나타낸다. 좌표는 `relative` 필드에 따라 절대좌표인지 상대좌표인지 결정된다. 또한, 스타일은 `style` 필드에 저장되어 있고, 이를 통해 컴포넌트의 색상, 선의 굵기, 폰트 등을 설정할 수 있다.

```xml
<mxCell id="131" value="Our Service" style="html=1;verticalAlign=top;strokeWidth=1;fillColor=#FFFFFF;fontStyle=0" parent="1" vertex="1">
    <mxGeometry x="-1670" y="828" width="144" height="271.67" as="geometry" />
</mxCell>
```

## Method

예상했던 대로 처음 몇 번의 시도 후에 알게된 것은 LLM이 XML을 읽고 다이어그램을 이해하는 것은 잘 해내지만, 다이어그램을 수정하고 재생성하는 작업은 잘 하지 못했다. 한 가지 문제는 우리에겐 다이어그램 데이터가 충분하지 않았다는 것이었다. 일반적으로, 다이어그램을 공유할 때 XML이 아닌 png와 같은 이미지로 공유하기 때문에, 우리가 가진 데이터는 XML이 아닌 이미지 데이터로 제한되어 있었다. 따라서 fine-tuning이나 RAG 등의 방법은 시도할 수 없었고, 다이어그램을 재생성하는 과정을 조금 더 세분화하는 것에 초점을 맞출 수 밖에 없었다.

### 어떤게 좋은 다이어그램인가?

또 하나의 문제점은 어떤 다이어그램이 좋은 다이어그램인지를 결정하는 것이었다. 앞서 언급했듯, 다이어그램은 과학보다는 예술의 영역에 가깝다. 따라서 좋은 다이어그램의 기준은 사람에 따라 달라질 수 있고, 같은 규칙이 상황에 따라 상반된 효과를 나타내기도 한다. ["Moody, D. (2007). What Makes a Good Diagram? Improving the Cognitive Effectiveness of Diagrams in IS Development"](https://link.springer.com/chapter/10.1007/978-0-387-70802-7_40) 논문에서는 다이어그램의 효과성을 결정하는 요소로 다음과 같은 것들을 제시한다. 우리는 이를 바탕으로 몇가지 규칙을 설정하였다.

- Discriminability
- Manageable Complexity
- Emphasis
- Cognitive Integrity
- Perceptual Directness
- Structure
- Identification
- Visual Expressiveneess
- Graphic Simplicity

### Image Input

우리는 이미지를 입력으로 받아서 이를 LLM에게 이해시키는 방법을 시도했다. 이 방법이 효과적이라면 사내의 무수히 많은 다이어그램들을 데이터로 사용할 수 있을 것이기에 가능성이 보인다면 가장 promising할 것으로 예상했다. 예상외로, LLM은 다이어그램 이미지로부터 Label을 인식하거나 컴포넌트 간의 연결관계를 파악하고 이해하는 수준에서는 꽤 괜찮은 성능을 보였다. 다만, 컴포넌트 간의 계층 관계를 이해하는 데에 문제가 있었고 결정적으로 output 토큰 제한인 4K를 초과하는 경우가 많았고 이를 줄일 수 있는 방법이 딱히 존재하지 않았기 때문에 다른 방법을 찾아보기로 했다.

### Few-shots

그 다음으로 시도한 방법은 few shots이었다. 몇몇 단순한 작업에 대해선 충분한 효과가 있었다. 예를 들어, Line style을 조정한다던가 shading을 준다던가하는 충분히 작고 단순한 작업에 대해서는 만족할 만한 결과가 도출되었다. 문제는 few-shots을 적용할 수 있는 작업들은 너무 한정적일 뿐더러, 이런 작업들은 굳이 few shots을 쓰지 않아도 해결할 수 있는 문제가 대부분이었다. 심지어는 코드를 이용해 스타일을 수정하는 것이 더 효과적인 작업도 있었다.

### Chain of Thougths

결국 우리는 mxGraph에 대한 상세한 부분을 프롬프트에 넣어주기 시작했다. 예를 들어, Line style을 결정하는 필드인 'strokeWidth'를 수정하면 된다고 알려주거나, 선의 배치를 조정하기 위해 설정해야 하는 필드인 'entryX', 'entryY', 'exitX', 'exitY' 등을 직접 알려주었다. 이렇게 하니, LLM의 성능이 확연히 향상되는 것을 보았지만, 아직도 우리가 원하는만큼 복잡한 작업을 수행하지는 못했다. 예를 들어, "아래의 예시에서 B를 A와 C에 orthogonal하게 배치해봐"라고 쿼리를 주었을 때, B를 잘 배치하고 A와 C에 연결된 선을 깔끔하게 다시 배치하는 작업은 아직도 LLM에게는 어려운 작업인 것처럼 보였다.

예시:

```txt
Delete all `mxCell` with `edge="1"` that has `source` or `target` as the corresponding ID.
```

````txt
ex) Calculate the midpoint of the lines using the pseudocode below.
```pseudocode
startPoint = (source.x + source.width * exitX, source.y + source.height * exitY)
endPoint = (target.x + target.width * entryX, target.y + target.height * entryY)
midpoint = (startPoint + endPoint) / 2
```
````

### 새로운 데이터 형태 제시

또 다른 두 가지의 문제점이 있었다. 첫번째는 토큰 개수이다. XML로 이루어진 다이어그램은 아무리 단순한 다이어그램이라도 4K로 제한된 LLM의 output token limit을 넘기기 십상이었다. 두번째로 LLM은 XML에서 계층 관계 (하나의 컴포넌트가 다른 컴포넌트에 속하는 관계)를 잘 이해하지 못하는 것처럼 보였다. 이게 중요한 이유는 컴포넌트 간의 포함관계는 LLM에 의한 수정 작업 이후에도 반드시 유지되어야 하는데, 유지되지 않는 경우가 상당히 많았다.
그래서 우리는 JSON으로 이루어진 새로운 데이터 형태를 제시했다. XML을 parsing하거나 재구성하는 코드를 직접 만들어놓고 JSON을 주었더니 최대 5분의 1까지 토큰 수가 줄어드는 것을 확인했고, 계층 구조도 잘 이해하는 것처럼 보였다. 그러나 문제는 복잡한 작업을 지시할 수록 토큰 감소 효과가 줄어들어 때로는 4K 제한을 넘기는 경우도 발생했고, 어플리케이션 자체의 복잡도도 너무 증가해버렸다. 결국 우리는 이 접근을 보류하기로 결정했다.

## 결과

비교적 단순한 작업에 대해선 유저가 지시한대로 다이어그램을 수정하는 챗봇이 완성되었다. 그러나, 다이어그램이 복잡해질수록 원하는 결과를 얻기가 매우 어렵고, 특히 deterministic한 결과를 얻을 수 있도록 프롬프트를 작업하는 것이 불가능에 가깝다고 여겨졌다. 결국, 데이터를 더 많이 확보해야만 할 것으로 결론을 내리고 프로젝트를 마무리했다.

## Reference

- Moody, D. (2007). What Makes a Good Diagram? Improving the Cognitive Effectiveness of Diagrams in IS Development. In: Wojtkowski, W., Wojtkowski, W.G., Zupancic, J., Magyar, G., Knapp, G. (eds) Advances in Information Systems Development. Springer, Boston, MA. <https://doi.org/10.1007/978-0-387-70802-7_40>
- <https://drawio-app.com/blog/what-makes-a-diagram-a-good-diagram/>
