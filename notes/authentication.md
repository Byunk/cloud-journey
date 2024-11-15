# Authentication

- [Authentication](#authentication)
  - [Token](#token)
  - [Certificate](#certificate)
    - [CA (Certificate Authority)](#ca-certificate-authority)
    - [Certificate Chain](#certificate-chain)
    - [CSR (Certificate Signing Request)](#csr-certificate-signing-request)
  - [TLS (Transport Layer Security)](#tls-transport-layer-security)
    - [TLS Termination](#tls-termination)
    - [TLS Passthrough](#tls-passthrough)
    - [TLS Bridging](#tls-bridging)
    - [SNI (Server Name Indication)](#sni-server-name-indication)
    - [`.pem` vs `.crt` vs `.key`](#pem-vs-crt-vs-key)
  - [Reference](#reference)

## Token

A token is a symmetric key. Both the server and the client share the same token to authenticate the sender of the HTTP request. Both token and session are ways to impose a status on stateless HTTP requests. For the token, the status is managed on the client side; a session is managed by the server.

The server is typically where the token is generated using the server's private key. It is sent from the server to the client at the first time and resent by the client whenever the client sends a request. JWT (JSON Web Token) is a proposed Internet standard way to encrypt JSON objects containing claims and is generally used.

## Certificate

A certificate is a digital document that facilitates authentication on the internet and adheres to the [X.509 standard](https://en.wikipedia.org/wiki/X.509). For two entities to communicate over the internet, it is essential for them to trust one another, ensuring they are indeed the intended parties in the conversation. Without this trust, both parties are susceptible to various vulnerabilities, including [man-in-the-middle (MITM) attacks](https://en.wikipedia.org/wiki/Man-in-the-middle_attack), where an attacker could intercept or alter the communication.

To address this issue, [CAs](#ca-certificate-authority) are introduced. A CA is a generally trusted entity that issues certificates with specific attributes to identify each communicating party. This process ensures that the identities of the entities are authenticated, thereby establishing a trusted communication channel.

> [A certificate is bound to a fully qualified domain name or (not usually) IP address.](https://stackoverflow.com/questions/1095780/are-ssl-certificates-bound-to-the-servers-ip-address)

### CA (Certificate Authority)

A CA is a publicly trusted entity that issues a digital certificate to a particular entity. A CA verifies an entity and creates a certificate that contains the public key and globally unique identifying information about the owner of the public key. And it is signed by the CA's private key. X.509 is a standard for CAs by ITU and IETF.

Since most browsers (possibly OS) include a set of trusted CA certificates when they are installed, certificates can be used to verify the trust chain presented by the server. The certificates installed in a browser can expire, even though they tend to have exceptionally long validity. With the update of browsers or OS, they can refresh root CAs before the old ones expired.

### Certificate Chain

CAs are classified as a Root CA and an Intermediate CA (ICA). A Root CA is self-signed, so the major browsers include the trust stores for the Root CAs. On the other hand, an ICA is signed by the higher level of CA, which constructs a certificate hierarchy.

Let's assume that company A issues an ICA. It has to be signed by the Root CA's private key so that it would be certified with the Root CA's public key. Next, if A issues a certificate to an application B. To verify this certificate, the end user should successively verify the certificate by A's public key and Root CA's public key. It is called a certificate chain.

### CSR (Certificate Signing Request)

CSR is a standard format to request a certificate. It consists of certificate request information, a signature algorithm identifier, and a digital signature on the certification request information. The certification request information includes the entity's distinguished name, the entity's public key, and a set of attributes providing other information about the entity.

The certification request information is signed with the entity's private key and decrypted by the CA. The CA then authenticates the entity and generates an X.509 certificate from the distinguished name and public key, the issuer's name, and the certification authority's choice of serial number, validity period, and signature algorithm.

## TLS (Transport Layer Security)

During the TLS handshake, first, the client sends the server a hello message. The server responds with its certificate, which contains its public key. The client verifies the server has been certified by a CA. Then the client generates a Master Secret (MS) and encrypts the MS with the server's public key to create the Encrypted Master Secret (EMS), and sends it to the server. The server decrypts the EMS with its private key. After this phase, all the messages from both the server and the client are encrypted with the shared MS.

### TLS Termination

![tls-termination](https://upload.wikimedia.org/wikipedia/commons/thumb/3/34/SSL_termination_proxy.svg/2560px-SSL_termination_proxy.svg.png)

A TLS termination proxy decrypts all incoming HTTPS traffic (offloading) and sends the decrypted data to the destination server over plain HTTP. However, it is vulnerable to man-in-the-middle attacks. Additionally, the private key used to decrypt/encrypt traffic needs to be stored on the proxy server.

### TLS Passthrough

A TLS passthrough proxy passes the incoming HTTPS traffic directly to the destination server. The major drawback of TLS passthrough is that if the incoming traffic may include malicious codes, there is no way to detect it before it reaches the internal server.

### TLS Bridging

A TLS bridging proxy offloads the incoming HTTPS traffic and encrypts it again when sending the data to the destination server. Within the proxy, it is possible to ensure that there is no malware in the payload. The drawbacks of TLS bridging are the costs of encryption/decryption and false positives (the proxy can discard innocent traffic).

### SNI (Server Name Indication)

[SNI](https://www.rfc-editor.org/rfc/rfc6066#section-3) is a mechanism by which the client securely indicates the real destination to the server that hosts multiple virtual servers. Since an HTTPS request is encrypted, there is no way to know where the request is going. SNI is included in the TLS client hello message so that the server receives unencrypted information about the destination.

### `.pem` vs `.crt` vs `.key`

`.key` files are generally the private key, used by the server to encrypt and package data for verification by clients.

`.pem` files are generally the public key, used by the client to verify and decrypt data sent by servers. PEM files could also be encoded private keys, so check the content if you're not sure.

`.p12` files have both halves of the key embedded, so that administrators can easily manage halves of keys.

`.cert` or `.crt` files are the signed certificates -- basically the "magic" that allows certain sites to be marked as trustworthy by a third party.

`.csr` is a certificate signing request, a challenge used by a trusted third party to verify the ownership of a keypair without having direct access to the private key (this is what allows end users, who have no direct knowledge of your website, confident that the certificate is valid). In the self-signed scenario you will use the certificate signing request with your own private key to verify your private key (thus self-signed). Depending on your specific application, this might not be needed. (needed for web servers or RPC servers, but not much else).

## Reference

- Kurose, J. and Ross, K. (2012) Computer Networking: A Top-Down Approach. Pearson, 6th Edition.
